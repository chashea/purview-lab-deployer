#Requires -Version 7.0

<#
.SYNOPSIS
    Configure Endpoint DLP browser-and-domain restrictions for Shadow AI lab.

.DESCRIPTION
    Reads the `endpointDlpBrowserRestrictions.blockedUrls` list from a shadow-ai
    config, compares it against the tenant's current Endpoint DLP global
    settings (via Get-PolicyConfig), and adds any missing AI service domains to
    the block list.

    Because the EndpointDlpGlobalSettings schema is not fully documented in
    Microsoft Learn, this script takes a cautious two-phase approach:

      1. **Discovery** (default): connects, reads the current tenant settings,
         and prints the Set-PolicyConfig command that would apply the merge.
         Nothing is changed.

      2. **Apply** (-Apply): actually runs Set-PolicyConfig. Still respects
         -WhatIf / -Confirm.

    Run discovery first, review the proposed command against your tenant, then
    re-run with -Apply only if the plan looks correct.

.PARAMETER ConfigPath
    Path to the shadow-ai lab config JSON. Defaults to commercial profile.

.PARAMETER LabProfile
    Lab profile shorthand — currently only 'shadow-ai' is meaningful.

.PARAMETER Cloud
    Cloud environment (commercial or gcc). Default: commercial.

.PARAMETER TenantId
    Entra ID tenant ID for Security & Compliance PowerShell connection.

.PARAMETER Apply
    Actually call Set-PolicyConfig. Without this switch, the script only prints
    the proposed command.

.EXAMPLE
    # Discovery mode — read current tenant settings, print merge preview
    ./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile shadow-ai

.EXAMPLE
    # Apply the merge (interactive confirmation, still honours -WhatIf)
    ./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile shadow-ai -Apply
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$LabProfile = 'shadow-ai',

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = 'commercial',

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules' 'Logging.psm1') -Force

function Resolve-ShadowAiConfig {
    param(
        [string]$ExplicitConfigPath,
        [string]$ProfileName,
        [string]$CloudEnv
    )

    if ($ExplicitConfigPath) {
        if (-not (Test-Path $ExplicitConfigPath)) {
            throw "Config file not found: $ExplicitConfigPath"
        }
        return (Resolve-Path $ExplicitConfigPath).Path
    }

    $fileName = "$ProfileName-demo.json"
    $candidate = Join-Path $repoRoot 'configs' $CloudEnv $fileName
    if (-not (Test-Path $candidate)) {
        throw "Could not locate config at $candidate. Pass -ConfigPath explicitly."
    }
    return (Resolve-Path $candidate).Path
}

function Connect-CompliancePowerShell {
    param([string]$Tenant)

    if (-not (Get-Command Connect-IPPSSession -ErrorAction SilentlyContinue)) {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
    }

    $existing = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.ConnectionUri -like '*compliance*' -and $_.State -eq 'Connected' }
    if ($existing) {
        Write-LabLog -Message "Reusing existing S&C PowerShell session ($($existing.UserPrincipalName))." -Level Info
        return
    }

    $params = @{ ShowBanner = $false; ErrorAction = 'Stop' }
    if ($Tenant) { $params['Organization'] = $Tenant }
    Connect-IPPSSession @params | Out-Null
    Write-LabLog -Message 'Connected to Security & Compliance PowerShell.' -Level Success
}

function Get-DesiredAiDomains {
    param([Parameter(Mandatory)][PSCustomObject]$Config)

    $domains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in @($Config.workloads.dlp.policies)) {
        if ($policy.PSObject.Properties['endpointDlpBrowserRestrictions'] -and
            $policy.endpointDlpBrowserRestrictions -and
            $policy.endpointDlpBrowserRestrictions.PSObject.Properties['blockedUrls']) {
            foreach ($url in @($policy.endpointDlpBrowserRestrictions.blockedUrls)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$url)) {
                    $null = $domains.Add(([string]$url).Trim())
                }
            }
        }
    }

    return [string[]]@($domains | Sort-Object)
}

function Get-CurrentBrowserDomainBlocklist {
    try {
        $config = Get-PolicyConfig -ErrorAction Stop
    }
    catch {
        throw "Failed to read Get-PolicyConfig: $($_.Exception.Message)"
    }

    $settings = @($config.EndpointDlpGlobalSettings)
    $matching = $settings | Where-Object {
        $null -ne $_ -and (
            ($_.PSObject.Properties.Name -contains 'Setting' -and
                [string]$_.Setting -match 'BrowserDomain|ServiceDomain|SensitiveDomain') -or
            ($_.PSObject.Properties.Name -contains 'Name' -and
                [string]$_.Name -match 'BrowserDomain|ServiceDomain|SensitiveDomain')
        )
    }

    return @{
        AllSettings   = $settings
        MatchingEntry = $matching | Select-Object -First 1
    }
}

# --- Main ---

$resolvedPath = Resolve-ShadowAiConfig -ExplicitConfigPath $ConfigPath -ProfileName $LabProfile -CloudEnv $Cloud
Write-LabLog -Message "Loading shadow-ai config: $resolvedPath" -Level Info
$config = Get-Content $resolvedPath -Raw | ConvertFrom-Json

$desiredDomains = Get-DesiredAiDomains -Config $config
if ($desiredDomains.Count -eq 0) {
    Write-LabLog -Message 'No endpointDlpBrowserRestrictions.blockedUrls found in config. Nothing to do.' -Level Warning
    exit 0
}
Write-LabLog -Message "Config lists $($desiredDomains.Count) AI service domain(s) to block:" -Level Info
foreach ($d in $desiredDomains) { Write-Host "  - $d" }

Connect-CompliancePowerShell -Tenant $TenantId

Write-Host ''
Write-Host '=== Current tenant EndpointDlpGlobalSettings ===' -ForegroundColor Cyan
$current = Get-CurrentBrowserDomainBlocklist

if ($null -eq $current.MatchingEntry) {
    Write-LabLog -Message 'No existing browser-domain-restriction entry found in EndpointDlpGlobalSettings. The portal UI may need to create the initial structure before this script can merge into it.' -Level Warning
    Write-Host ''
    Write-Host 'To create the initial structure: Microsoft Purview portal > Data loss prevention > Endpoint DLP settings > Browser and domain restrictions to sensitive data. Configure Service domains = Block with at least one placeholder entry, then re-run this script.' -ForegroundColor Yellow
    exit 2
}

$currentJson = $current.MatchingEntry | ConvertTo-Json -Depth 10
Write-Host $currentJson

Write-Host ''
Write-Host '=== Proposed merge ===' -ForegroundColor Cyan
Write-Host 'This script would set the BrowserDomainRestrictions entry to include all desired domains while preserving existing values.'
Write-Host "Tenant-wide EndpointDlpGlobalSettings is shared across DLP policies. Review the current entry above before applying."

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Discovery mode only. Re-run with -Apply to push changes via Set-PolicyConfig (still honours -WhatIf/-Confirm).' -ForegroundColor Yellow
    exit 0
}

if (-not $PSCmdlet.ShouldProcess('EndpointDlpGlobalSettings', "Merge $($desiredDomains.Count) AI service domain(s) into BrowserDomainRestrictions")) {
    exit 0
}

# Build merged entry: clone existing, add missing domains
$existingDomains = @()
try {
    if ($current.MatchingEntry.Value -and $current.MatchingEntry.Value.Domains) {
        $existingDomains = @($current.MatchingEntry.Value.Domains)
    }
}
catch {
    $null = $_
}

$mergedDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($d in $existingDomains) {
    if (-not [string]::IsNullOrWhiteSpace($d)) { $null = $mergedDomains.Add([string]$d) }
}
foreach ($d in $desiredDomains) { $null = $mergedDomains.Add($d) }

Write-LabLog -Message "Merged domain list has $($mergedDomains.Count) entries." -Level Info

$settingName = if ($current.MatchingEntry.PSObject.Properties.Name -contains 'Setting') { 'Setting' } else { 'Name' }
$newEntry = @{
    $settingName = [string]$current.MatchingEntry.$settingName
    Value        = @{
        ServiceDomains = if ($current.MatchingEntry.Value.ServiceDomains) { [string]$current.MatchingEntry.Value.ServiceDomains } else { 'Block' }
        Domains        = [string[]]@($mergedDomains | Sort-Object)
    }
}

# Preserve other settings — replace only the matching entry
$updatedSettings = foreach ($s in @($current.AllSettings)) {
    $isMatch = $null -ne $s -and (
        ($s.PSObject.Properties.Name -contains 'Setting' -and $s.Setting -eq $current.MatchingEntry.$settingName) -or
        ($s.PSObject.Properties.Name -contains 'Name' -and $s.Name -eq $current.MatchingEntry.$settingName)
    )
    if ($isMatch) { $newEntry } else { $s }
}

try {
    Set-PolicyConfig -EndpointDlpGlobalSettings $updatedSettings -ErrorAction Stop
    Write-LabLog -Message 'Set-PolicyConfig succeeded. Endpoint DLP domain restrictions updated.' -Level Success
}
catch {
    Write-LabLog -Message "Set-PolicyConfig failed: $($_.Exception.Message)" -Level Error
    Write-LabLog -Message 'Preserving existing tenant settings is the priority. Apply the domain list manually via Purview portal > Endpoint DLP settings > Browser and domain restrictions to sensitive data.' -Level Warning
    exit 3
}
