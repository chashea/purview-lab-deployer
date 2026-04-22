#Requires -Version 7.0

<#
.SYNOPSIS
    Pre-demo readiness check for the Copilot DLP Guardrails lab.

.DESCRIPTION
    DLP policy changes take up to 4 hours to fully reflect in Microsoft 365
    Copilot and Copilot Chat. This silently breaks demos when the presenter
    assumes deployment = ready. This script reports whether the lab is actually
    ready to demo.

    Checks performed:

      1. DLP policies from the config exist in the tenant
         (both Copilot Prompt SIT Block and Copilot Labeled Content Block)
      2. Policy Mode (TestWithNotifications vs. Enable) matches expectation
      3. LastModifiedTime + 4-hour propagation window -> ETA
      4. Sensitivity labels referenced by label-based rules exist
      5. At least one label policy publishes them to the demo users
      6. Demo users from config have a Microsoft 365 Copilot license assigned

    Output: a readiness table and an overall verdict (Ready / Wait / Blocked).

.PARAMETER ConfigPath
    Path to the Copilot DLP lab config JSON. Defaults to the commercial profile.

.PARAMETER LabProfile
    Lab profile shorthand. Accepts 'copilot-protection' or legacy 'copilot-dlp'.

.PARAMETER Cloud
    Cloud environment (commercial or gcc). Default: commercial.

.PARAMETER TenantId
    Entra ID tenant ID. Used for Graph + S&C authentication.

.PARAMETER SkipLicenseCheck
    Skip the Microsoft Graph call that verifies demo users have Copilot
    licenses. Useful when running without Graph consent.

.EXAMPLE
    ./scripts/Test-CopilotDlpReady.ps1 -LabProfile ai -Cloud commercial

.EXAMPLE
    ./scripts/Test-CopilotDlpReady.ps1 -ConfigPath ./configs/commercial/ai-demo.json -TenantId 00000000-0000-0000-0000-000000000000
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$LabProfile,

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = 'commercial',

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [switch]$SkipLicenseCheck
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

Import-Module (Join-Path $repoRoot 'modules' 'Logging.psm1') -Force

# Microsoft 365 Copilot SKU — stable GUID per Microsoft licensing docs.
$CopilotSkuId = '639dec6b-bb19-468b-871c-c5c441c4b0cb'
$PropagationWindowHours = 4

function Resolve-LabConfigPath {
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

    $profileSlug = if ($ProfileName) {
        switch ($ProfileName) {
            'copilot-protection' { 'ai-demo.json' }
            'copilot-dlp'        { 'ai-demo.json' }
            'ai-security'        { 'ai-demo.json' }
            'shadow-ai'          { 'ai-demo.json' }
            'ai'                 { 'ai-demo.json' }
            default              { "$ProfileName-demo.json" }
        }
    }
    else {
        'ai-demo.json'
    }

    $candidate = Join-Path $repoRoot 'configs' $CloudEnv $profileSlug
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
    if ($Tenant) {
        $params['Organization'] = $Tenant
    }
    Connect-IPPSSession @params | Out-Null
    Write-LabLog -Message 'Connected to Security & Compliance PowerShell.' -Level Success
}

function Connect-GraphForReadiness {
    param([string]$Tenant)

    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    }

    $existingContext = Get-MgContext -ErrorAction SilentlyContinue
    if ($existingContext -and $existingContext.Scopes -contains 'User.Read.All') {
        Write-LabLog -Message "Reusing existing Microsoft Graph session ($($existingContext.Account))." -Level Info
        return
    }

    $params = @{
        Scopes      = @('User.Read.All', 'Directory.Read.All')
        NoWelcome   = $true
        ErrorAction = 'Stop'
    }
    if ($Tenant) {
        $params['TenantId'] = $Tenant
    }
    Connect-MgGraph @params | Out-Null
    Write-LabLog -Message 'Connected to Microsoft Graph.' -Level Success
}

function Get-CopilotDlpPolicyReadiness {
    param(
        [Parameter(Mandatory)] [PSCustomObject]$Config,
        [Parameter(Mandatory)] [datetime]$Now
    )

    $results = @()
    $simulation = [bool]$Config.workloads.dlp.simulationMode
    $expectedMode = if ($simulation) { 'TestWithNotifications' } else { 'Enable' }

    foreach ($policy in @($Config.workloads.dlp.policies)) {
        $policyName = "$($Config.prefix)-$($policy.name)"
        $status = [ordered]@{
            Check      = "DLP policy: $policyName"
            Exists     = $false
            Mode       = $null
            ExpectedMode = $expectedMode
            ETA        = $null
            State      = 'Blocked'
            Detail     = $null
        }

        $dlpPolicy = $null
        try {
            $dlpPolicy = Get-DlpCompliancePolicy -Identity $policyName -ErrorAction Stop
        }
        catch {
            $status.Detail = 'Policy not found — run Deploy-Lab.ps1 first.'
            $results += [pscustomobject]$status
            continue
        }

        $status.Exists = $true
        $status.Mode = [string]$dlpPolicy.Mode

        $lastModified = $null
        if ($dlpPolicy.PSObject.Properties.Name -contains 'WhenChangedUTC' -and $dlpPolicy.WhenChangedUTC) {
            $lastModified = [datetime]$dlpPolicy.WhenChangedUTC
        }
        elseif ($dlpPolicy.PSObject.Properties.Name -contains 'LastModifiedTime' -and $dlpPolicy.LastModifiedTime) {
            $lastModified = [datetime]$dlpPolicy.LastModifiedTime
        }

        if ($lastModified) {
            $readyAt = $lastModified.AddHours($PropagationWindowHours)
            $status.ETA = $readyAt.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
            if ($Now -lt $readyAt) {
                $minutesLeft = [math]::Ceiling(($readyAt - $Now).TotalMinutes)
                $status.State = 'Wait'
                $status.Detail = "Propagating — ~$minutesLeft min remaining (policies take up to 4h to reflect in Copilot)."
            }
            else {
                $status.State = 'Ready'
                $status.Detail = 'Past 4h propagation window.'
            }
        }
        else {
            $status.State = 'Ready'
            $status.Detail = 'Policy exists; no modification timestamp available.'
        }

        if ($status.Mode -and $status.Mode -ne $expectedMode) {
            $status.State = 'Wait'
            $status.Detail = "Mode is '$($status.Mode)'; expected '$expectedMode'. Switch in portal or redeploy (then wait 4h)."
        }

        $results += [pscustomobject]$status
    }

    return $results
}

function Get-CopilotLabelReadiness {
    param([Parameter(Mandatory)] [PSCustomObject]$Config)

    $results = @()

    $expectedLabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in @($Config.workloads.dlp.policies)) {
        foreach ($labelName in @($policy.labels)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$labelName)) {
                $null = $expectedLabels.Add([string]$labelName)
            }
        }
        foreach ($rule in @($policy.rules)) {
            foreach ($labelName in @($rule.labels)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$labelName)) {
                    $null = $expectedLabels.Add([string]$labelName)
                }
            }
        }
    }

    if ($expectedLabels.Count -eq 0) {
        return $results
    }

    $allLabels = @()
    try {
        $allLabels = Get-Label -ErrorAction Stop
    }
    catch {
        foreach ($labelName in $expectedLabels) {
            $results += [pscustomobject]@{
                Check  = "Label: $labelName"
                State  = 'Blocked'
                Detail = "Could not query labels: $($_.Exception.Message)"
            }
        }
        return $results
    }

    $labelPolicies = @()
    try {
        $labelPolicies = Get-LabelPolicy -ErrorAction Stop
    }
    catch {
        Write-LabLog -Message "Could not query label policies: $($_.Exception.Message)" -Level Warning
    }

    foreach ($labelName in $expectedLabels) {
        $match = $allLabels | Where-Object {
            $_.Name -eq $labelName -or $_.DisplayName -eq $labelName -or [string]$_.Identity -eq $labelName
        } | Select-Object -First 1

        if (-not $match) {
            $results += [pscustomobject]@{
                Check  = "Label: $labelName"
                State  = 'Blocked'
                Detail = 'Sensitivity label does not exist — redeploy SensitivityLabels workload.'
            }
            continue
        }

        $published = $false
        foreach ($labelPolicy in $labelPolicies) {
            if (@($labelPolicy.Labels) -contains [string]$match.Guid -or @($labelPolicy.Labels) -contains $match.Name) {
                $published = $true
                break
            }
        }

        $results += [pscustomobject]@{
            Check  = "Label: $($match.DisplayName)"
            State  = if ($published) { 'Ready' } else { 'Wait' }
            Detail = if ($published) { "Published (GUID: $($match.Guid))" } else { 'Label exists but is not published to any policy. Publish via Information Protection > Label policies.' }
        }
    }

    return $results
}

function Get-CopilotLicenseReadiness {
    param([Parameter(Mandatory)] [PSCustomObject]$Config)

    $results = @()
    $demoUpns = @()
    foreach ($user in @($Config.workloads.testUsers.users)) {
        if ($user.upn) { $demoUpns += [string]$user.upn }
    }

    foreach ($upn in $demoUpns) {
        $check = [ordered]@{
            Check  = "License: $upn"
            State  = 'Blocked'
            Detail = $null
        }

        try {
            $licenses = Get-MgUserLicenseDetail -UserId $upn -ErrorAction Stop
            $hasCopilot = $licenses | Where-Object { $_.SkuId -eq $CopilotSkuId }
            if ($hasCopilot) {
                $check.State = 'Ready'
                $check.Detail = 'Microsoft 365 Copilot license assigned.'
            }
            else {
                $check.State = 'Blocked'
                $check.Detail = 'No Microsoft 365 Copilot license assigned. Assign before demo.'
            }
        }
        catch {
            $check.Detail = "Graph query failed: $($_.Exception.Message)"
        }

        $results += [pscustomobject]$check
    }

    return $results
}

function Write-ReadinessTable {
    param([array]$Results)

    $results | Select-Object Check, State, Detail | Format-Table -AutoSize -Wrap | Out-String | Write-Host
}

# ---- Main ----

$resolvedPath = Resolve-LabConfigPath -ExplicitConfigPath $ConfigPath -ProfileName $LabProfile -CloudEnv $Cloud
Write-LabLog -Message "Loading config: $resolvedPath" -Level Info
$config = Get-Content $resolvedPath -Raw | ConvertFrom-Json

if (-not $config.workloads.dlp) {
    throw "Config '$resolvedPath' has no DLP workload. Is this a Copilot DLP lab?"
}

Connect-CompliancePowerShell -Tenant $TenantId

$now = Get-Date
$allResults = @()
$allResults += Get-CopilotDlpPolicyReadiness -Config $config -Now $now
$allResults += Get-CopilotLabelReadiness -Config $config

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
Write-Host '=== Copilot DLP Readiness ===' -ForegroundColor Cyan
Write-ReadinessTable -Results $allResults

$blocked = @($allResults | Where-Object { $_.State -eq 'Blocked' })
$waiting = @($allResults | Where-Object { $_.State -eq 'Wait' })

if ($blocked.Count -gt 0) {
    Write-Host "VERDICT: BLOCKED — $($blocked.Count) item(s) require action before demo." -ForegroundColor Red
    exit 2
}
elseif ($waiting.Count -gt 0) {
    Write-Host "VERDICT: WAIT — $($waiting.Count) item(s) still propagating or unpublished." -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host 'VERDICT: READY — Copilot DLP lab is demo-ready.' -ForegroundColor Green
    exit 0
}
