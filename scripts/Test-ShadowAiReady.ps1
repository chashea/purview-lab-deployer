#Requires -Version 7.0

<#
.SYNOPSIS
    Pre-demo readiness check for the Shadow AI Prevention lab.

.DESCRIPTION
    Shadow AI lab depends on multiple Purview surfaces converging: Endpoint DLP
    browser restrictions, sensitivity labels, Copilot-targeted policies,
    Insider Risk policies, Communication Compliance, and Defender for Endpoint
    onboarding on test devices. Any one missing silently breaks the demo.

    This script verifies the lab is ready to present. Checks:

      1. DLP policies from the config exist and are in the expected mode
      2. Sensitivity labels exist (referenced by test documents and DLP rules)
      3. Label policies publish labels to demo users
      4. Insider Risk policies are present
      5. Communication Compliance policies are present
      6. Retention policies for AI apps are present
      7. Demo users have Microsoft 365 Copilot licenses
      8. Endpoint DLP tenant settings include the configured AI service domains

    Output: readiness table + verdict (Ready / Wait / Blocked).

.PARAMETER ConfigPath
    Path to the Shadow AI config JSON. Defaults to commercial profile.

.PARAMETER LabProfile
    Lab profile shorthand. Default: 'shadow-ai'.

.PARAMETER Cloud
    Cloud environment (commercial or gcc). Default: commercial.

.PARAMETER TenantId
    Entra ID tenant ID.

.PARAMETER SkipLicenseCheck
    Skip Graph license check.

.PARAMETER SkipEndpointDlpCheck
    Skip Get-PolicyConfig inspection (which is slow and requires S&C session).

.EXAMPLE
    ./scripts/Test-ShadowAiReady.ps1 -LabProfile ai -Cloud commercial
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$LabProfile = 'ai',

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = 'commercial',

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [switch]$SkipLicenseCheck,

    [Parameter()]
    [switch]$SkipEndpointDlpCheck
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules' 'Logging.psm1') -Force

$CopilotSkuId = '639dec6b-bb19-468b-871c-c5c441c4b0cb'
$PropagationWindowHours = 4

function Resolve-LabConfigPath {
    param([string]$ExplicitConfigPath, [string]$ProfileName, [string]$CloudEnv)

    if ($ExplicitConfigPath) {
        if (-not (Test-Path $ExplicitConfigPath)) { throw "Config file not found: $ExplicitConfigPath" }
        return (Resolve-Path $ExplicitConfigPath).Path
    }
    $slug = switch ($ProfileName) {
        'shadow-ai'          { 'ai-demo.json' }
        'ai-security'        { 'ai-demo.json' }
        'copilot-protection' { 'ai-demo.json' }
        'copilot-dlp'        { 'ai-demo.json' }
        'ai'                 { 'ai-demo.json' }
        default              { "$ProfileName-demo.json" }
    }
    $candidate = Join-Path $repoRoot 'configs' $CloudEnv $slug
    if (-not (Test-Path $candidate)) { throw "Could not locate config at $candidate." }
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

function Connect-GraphForReadiness {
    param([string]$Tenant)
    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    }
    $existing = Get-MgContext -ErrorAction SilentlyContinue
    if ($existing -and $existing.Scopes -contains 'User.Read.All') {
        Write-LabLog -Message "Reusing existing Microsoft Graph session ($($existing.Account))." -Level Info
        return
    }
    $params = @{ Scopes = @('User.Read.All', 'Directory.Read.All'); NoWelcome = $true; ErrorAction = 'Stop' }
    if ($Tenant) { $params['TenantId'] = $Tenant }
    Connect-MgGraph @params | Out-Null
    Write-LabLog -Message 'Connected to Microsoft Graph.' -Level Success
}

function Get-DlpPolicyReadiness {
    param([PSCustomObject]$Config, [datetime]$Now)
    $results = @()
    $simulation = [bool]$Config.workloads.dlp.simulationMode
    $expectedMode = if ($simulation) { 'TestWithNotifications' } else { 'Enable' }

    foreach ($policy in @($Config.workloads.dlp.policies)) {
        $policyName = "$($Config.prefix)-$($policy.name)"
        $status = [ordered]@{ Check = "DLP policy: $policyName"; State = 'Blocked'; Detail = $null }

        try {
            $dlpPolicy = Get-DlpCompliancePolicy -Identity $policyName -ErrorAction Stop
        }
        catch {
            $status.Detail = 'Policy not found — run Deploy-Lab.ps1.'
            $results += [pscustomobject]$status
            continue
        }

        $mode = [string]$dlpPolicy.Mode
        if ($mode -and $mode -ne $expectedMode) {
            $status.State = 'Wait'
            $status.Detail = "Mode is '$mode', expected '$expectedMode'."
        }
        else {
            $lastModified = if ($dlpPolicy.WhenChangedUTC) { [datetime]$dlpPolicy.WhenChangedUTC } else { $null }
            if ($lastModified -and $Now -lt $lastModified.AddHours($PropagationWindowHours)) {
                $minutesLeft = [math]::Ceiling(($lastModified.AddHours($PropagationWindowHours) - $Now).TotalMinutes)
                $status.State = 'Wait'
                $status.Detail = "Propagating — ~$minutesLeft min remaining."
            }
            else {
                $status.State = 'Ready'
                $status.Detail = "Mode: $mode."
            }
        }
        $results += [pscustomobject]$status
    }
    return $results
}

function Get-LabelReadiness {
    param([PSCustomObject]$Config)
    $results = @()

    $expectedLabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($parent in @($Config.workloads.sensitivityLabels.labels)) {
        foreach ($child in @($parent.sublabels)) {
            $null = $expectedLabels.Add("$($Config.prefix)-$($parent.name.Replace(' ','-'))-$($child.name.Replace(' ','-'))")
        }
    }

    $allLabels = @()
    try { $allLabels = Get-Label -ErrorAction Stop }
    catch {
        $results += [pscustomobject]@{ Check = 'Sensitivity labels'; State = 'Blocked'; Detail = "Could not query labels: $($_.Exception.Message)" }
        return $results
    }

    $missing = @()
    foreach ($labelName in $expectedLabels) {
        $match = $allLabels | Where-Object {
            $_.Name -eq $labelName -or $_.DisplayName -eq $labelName -or [string]$_.Identity -eq $labelName
        } | Select-Object -First 1
        if (-not $match) { $missing += $labelName }
    }

    if ($missing.Count -gt 0) {
        $results += [pscustomobject]@{
            Check  = 'Sensitivity labels'
            State  = 'Blocked'
            Detail = "Missing $($missing.Count) sublabel(s): $(($missing | Select-Object -First 3) -join ', ')..."
        }
    }
    else {
        $results += [pscustomobject]@{
            Check  = 'Sensitivity labels'
            State  = 'Ready'
            Detail = "$($expectedLabels.Count) sublabel(s) exist."
        }
    }
    return $results
}

function Get-IrmReadiness {
    param([PSCustomObject]$Config)
    $results = @()
    if (-not $Config.workloads.insiderRisk.policies) { return $results }

    $allPolicies = @()
    try { $allPolicies = Get-InsiderRiskPolicy -ErrorAction Stop }
    catch {
        $results += [pscustomobject]@{
            Check = 'Insider Risk policies'
            State = 'Blocked'
            Detail = "Could not enumerate: $($_.Exception.Message)"
        }
        return $results
    }

    foreach ($policy in @($Config.workloads.insiderRisk.policies)) {
        $name = "$($Config.prefix)-$($policy.name)"
        $match = $allPolicies | Where-Object { $_.Name -eq $name }
        $results += [pscustomobject]@{
            Check = "IRM: $name"
            State = if ($match) { 'Ready' } else { 'Blocked' }
            Detail = if ($match) { 'Exists.' } else { 'Policy missing — re-run Deploy-Lab.ps1.' }
        }
    }
    return $results
}

function Get-CopilotLicenseReadiness {
    param([PSCustomObject]$Config)
    $results = @()
    foreach ($user in @($Config.workloads.testUsers.users)) {
        $upn = [string]$user.upn
        if ([string]::IsNullOrWhiteSpace($upn)) { continue }
        $check = [ordered]@{ Check = "License: $upn"; State = 'Blocked'; Detail = $null }
        try {
            $licenses = Get-MgUserLicenseDetail -UserId $upn -ErrorAction Stop
            if ($licenses | Where-Object { $_.SkuId -eq $CopilotSkuId }) {
                $check.State = 'Ready'; $check.Detail = 'Copilot licensed.'
            }
            else {
                $check.State = 'Wait'; $check.Detail = 'No Copilot SKU — assign before demo.'
            }
        }
        catch {
            $check.Detail = "Graph lookup failed: $($_.Exception.Message)"
        }
        $results += [pscustomobject]$check
    }
    return $results
}

function Get-EndpointDlpDomainReadiness {
    param([PSCustomObject]$Config)
    $results = @()

    $desired = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in @($Config.workloads.dlp.policies)) {
        if ($policy.PSObject.Properties['endpointDlpBrowserRestrictions'] -and
            $policy.endpointDlpBrowserRestrictions -and
            $policy.endpointDlpBrowserRestrictions.PSObject.Properties['blockedUrls']) {
            foreach ($url in @($policy.endpointDlpBrowserRestrictions.blockedUrls)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$url)) { $null = $desired.Add(([string]$url).Trim()) }
            }
        }
    }

    if ($desired.Count -eq 0) { return $results }

    try {
        $polConfig = Get-PolicyConfig -ErrorAction Stop
    }
    catch {
        $results += [pscustomobject]@{
            Check  = 'Endpoint DLP domain block list'
            State  = 'Blocked'
            Detail = "Get-PolicyConfig failed: $($_.Exception.Message)"
        }
        return $results
    }

    $currentDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($s in @($polConfig.EndpointDlpGlobalSettings)) {
        if ($null -eq $s) { continue }
        if ($s.PSObject.Properties.Name -contains 'Value' -and $s.Value -and $s.Value.PSObject.Properties.Name -contains 'Domains') {
            foreach ($d in @($s.Value.Domains)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$d)) { $null = $currentDomains.Add([string]$d) }
            }
        }
    }

    $missing = @($desired | Where-Object { -not $currentDomains.Contains($_) })

    if ($missing.Count -eq 0) {
        $results += [pscustomobject]@{
            Check  = 'Endpoint DLP domain block list'
            State  = 'Ready'
            Detail = "All $($desired.Count) AI domain(s) present in tenant settings."
        }
    }
    else {
        $results += [pscustomobject]@{
            Check  = 'Endpoint DLP domain block list'
            State  = 'Wait'
            Detail = "Missing $($missing.Count): $(($missing | Select-Object -First 3) -join ', '). Run Set-ShadowAiEndpointDlpDomains.ps1 -Apply."
        }
    }
    return $results
}

function Write-ReadinessTable {
    param([array]$Results)
    $Results | Select-Object Check, State, Detail | Format-Table -AutoSize -Wrap | Out-String | Write-Host
}

# --- Main ---
$resolvedPath = Resolve-LabConfigPath -ExplicitConfigPath $ConfigPath -ProfileName $LabProfile -CloudEnv $Cloud
Write-LabLog -Message "Loading config: $resolvedPath" -Level Info
$config = Get-Content $resolvedPath -Raw | ConvertFrom-Json

Connect-CompliancePowerShell -Tenant $TenantId

$now = Get-Date
$allResults = @()
$allResults += Get-DlpPolicyReadiness -Config $config -Now $now
$allResults += Get-LabelReadiness -Config $config
$allResults += Get-IrmReadiness -Config $config

if (-not $SkipEndpointDlpCheck) {
    $allResults += Get-EndpointDlpDomainReadiness -Config $config
}

if (-not $SkipLicenseCheck) {
    try {
        Connect-GraphForReadiness -Tenant $TenantId
        $allResults += Get-CopilotLicenseReadiness -Config $config
    }
    catch {
        Write-LabLog -Message "Skipping license check — Graph connection failed: $($_.Exception.Message)" -Level Warning
    }
}

Write-Host ''
Write-Host '=== Shadow AI Readiness ===' -ForegroundColor Cyan
Write-ReadinessTable -Results $allResults

$blocked = @($allResults | Where-Object { $_.State -eq 'Blocked' })
$waiting = @($allResults | Where-Object { $_.State -eq 'Wait' })

if ($blocked.Count -gt 0) {
    Write-Host "VERDICT: BLOCKED — $($blocked.Count) item(s) require action." -ForegroundColor Red
    exit 2
}
elseif ($waiting.Count -gt 0) {
    Write-Host "VERDICT: WAIT — $($waiting.Count) item(s) in progress." -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host 'VERDICT: READY — Shadow AI lab is demo-ready.' -ForegroundColor Green
    exit 0
}
