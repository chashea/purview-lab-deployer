#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Live readiness check for DLP policies + alerts on the lab tenant.

.DESCRIPTION
    Diagnoses the most common reasons DLP policies don't show activity,
    alerts, or incidents:

      1. Policy not yet activated (takes ~1h after create/update).
      2. Alert surfacing window (up to 3h after alert config change).
      3. Rule alert misconfigured (GenerateAlert needs real SMTP; tokens
         like SiteAdmin/LastModifier are rejected for the alert dashboard).
      4. Rule disabled or policy disabled/PendingDeletion.
      5. Wrong enforcement mode (TestWithoutNotifications hides alerts).
      6. No new matching activity has been generated yet (Exchange DLP
         only scans *new* mail; SharePoint/OneDrive scan existing + new).

    Output: a readiness table per policy + per rule, an ETA window, and
    pointers to the two alert surfaces (Defender XDR + DLP dashboard).

.PARAMETER ConfigPath
    Path to the lab config JSON. Defaults to basic-demo for the chosen cloud.

.PARAMETER LabProfile
    Lab profile shorthand. Default: 'basic'.

.PARAMETER Cloud
    Cloud environment (commercial or gcc). Default: commercial.

.PARAMETER TenantId
    Entra ID tenant ID. Forwarded to Connect-IPPSSession.

.PARAMETER SkipAuditQuery
    Skip Search-UnifiedAuditLog for recent DLP rule matches. Useful when the
    role group doesn't grant audit search rights.

.EXAMPLE
    ./scripts/Test-DlpAlertReady.ps1 -LabProfile basic -Cloud commercial

.EXAMPLE
    ./scripts/Test-DlpAlertReady.ps1 -ConfigPath ./configs/commercial/basic-demo.json
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$LabProfile = 'basic',

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = 'commercial',

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [switch]$SkipAuditQuery
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules' 'Logging.psm1') -Force

$script:PolicyActivationHours = 1
$script:AlertSurfaceHours = 3

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

    $profileSlug = if ($ProfileName) { "$ProfileName-demo.json" } else { 'basic-demo.json' }
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
        Write-LabLog -Message "Reusing S&C PowerShell session ($($existing.UserPrincipalName))." -Level Info
        return
    }

    $params = @{ ShowBanner = $false; ErrorAction = 'Stop' }
    if ($Tenant) { $params['Organization'] = $Tenant }
    Connect-IPPSSession @params | Out-Null
    Write-LabLog -Message 'Connected to Security & Compliance PowerShell.' -Level Success
}

function Format-AlertRecipients {
    param($Value)

    if ($null -eq $Value) { return '' }
    $items = @($Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    if ($items.Count -eq 0) { return '' }
    return ($items -join '; ')
}

function Test-RealSmtp {
    param([string[]]$Recipients)
    if (-not $Recipients) { return $false }
    foreach ($r in $Recipients) {
        if ($r -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return $true }
    }
    return $false
}

function Get-PolicyReadiness {
    param(
        [Parameter(Mandatory)] [PSCustomObject]$Config,
        [Parameter(Mandatory)] [datetime]$Now
    )

    $results = @()
    $simulation = [bool]$Config.workloads.dlp.simulationMode
    $expectedMode = if ($simulation) { 'TestWithNotifications' } else { 'Enable' }

    foreach ($policy in @($Config.workloads.dlp.policies)) {
        $policyName = "$($Config.prefix)-$($policy.name)"

        $entry = [ordered]@{
            Policy         = $policyName
            Exists         = $false
            Mode           = $null
            ExpectedMode   = $expectedMode
            Enabled        = $null
            LastModified   = $null
            AlertETA       = $null
            State          = 'Blocked'
            Detail         = $null
        }

        try {
            $live = Get-DlpCompliancePolicy -Identity $policyName -ErrorAction Stop
        }
        catch {
            $entry.Detail = "Policy not found in tenant: $($_.Exception.Message)"
            $results += [pscustomobject]$entry
            continue
        }

        $entry.Exists = $true
        $entry.Mode = [string]$live.Mode
        $entry.Enabled = [bool]$live.Enabled
        $lastMod = [datetime]$live.WhenChangedUTC
        if (-not $lastMod -and $live.WhenCreatedUTC) { $lastMod = [datetime]$live.WhenCreatedUTC }
        $entry.LastModified = $lastMod

        $alertEta = $lastMod.AddHours($script:AlertSurfaceHours)
        $entry.AlertETA = $alertEta

        $issues = @()
        if (-not $entry.Enabled) { $issues += 'policy disabled' }
        if ($entry.Mode -eq 'Disable') { $issues += 'Mode=Disable (alerts suppressed)' }
        if ($entry.Mode -eq 'PendingDeletion') { $issues += 'Mode=PendingDeletion' }
        if ($entry.Mode -eq 'TestWithoutNotifications') { $issues += 'Mode=TestWithoutNotifications (no user notifications or alerts)' }
        if ($entry.Mode -ne $expectedMode -and -not ($issues)) { $issues += "Mode=$($entry.Mode), config expected $expectedMode" }

        if ($alertEta -gt $Now) {
            $minsLeft = [int]($alertEta - $Now).TotalMinutes
            $issues += "alert surface window open (~${minsLeft} min remaining)"
            $entry.State = 'Wait'
        }
        elseif ($issues.Count -gt 0) {
            $entry.State = 'Blocked'
        }
        else {
            $entry.State = 'Ready'
        }

        $entry.Detail = ($issues -join '; ')
        $results += [pscustomobject]$entry
    }

    return $results
}

function Get-RuleReadiness {
    param([Parameter(Mandatory)] [PSCustomObject]$Config)

    $results = @()

    foreach ($policy in @($Config.workloads.dlp.policies)) {
        $policyName = "$($Config.prefix)-$($policy.name)"
        foreach ($rule in @($policy.rules)) {
            $ruleName = "$($Config.prefix)-$($rule.name)"
            $entry = [ordered]@{
                Policy           = $policyName
                Rule             = $ruleName
                Exists           = $false
                Disabled         = $null
                Mode             = $null
                BlockAccess      = $null
                ReportSeverity   = $null
                GenerateAlert    = $null
                AlertHasSmtp     = $null
                NotifyUser       = $null
                IncidentReport   = $null
                State            = 'Blocked'
                Detail           = $null
            }

            try {
                $live = Get-DlpComplianceRule -Identity $ruleName -ErrorAction Stop
            }
            catch {
                $entry.Detail = "Rule not found: $($_.Exception.Message)"
                $results += [pscustomobject]$entry
                continue
            }

            $entry.Exists = $true
            $entry.Disabled = [bool]$live.Disabled
            $entry.Mode = [string]$live.Mode
            $entry.BlockAccess = [string]$live.BlockAccess
            $entry.ReportSeverity = [string]$live.ReportSeverityLevel

            $alertRecipients = @($live.GenerateAlert)
            $entry.GenerateAlert = Format-AlertRecipients $alertRecipients
            $entry.AlertHasSmtp = Test-RealSmtp $alertRecipients
            $entry.NotifyUser = Format-AlertRecipients $live.NotifyUser
            $entry.IncidentReport = Format-AlertRecipients $live.GenerateIncidentReport

            $issues = @()
            if ($entry.Disabled) { $issues += 'rule disabled' }
            if (-not $alertRecipients -or $alertRecipients.Count -eq 0) {
                $issues += 'GenerateAlert empty (no alert will surface)'
            }
            elseif (-not $entry.AlertHasSmtp) {
                $issues += 'GenerateAlert has only tokens (no real SMTP) — server may drop the alert silently'
            }
            if (-not $entry.ReportSeverity) {
                $issues += 'no ReportSeverityLevel — alert may not appear in dashboard filters'
            }

            if ($entry.Disabled -or -not $entry.GenerateAlert) {
                $entry.State = 'Blocked'
            }
            elseif ($issues.Count -gt 0) {
                $entry.State = 'Warn'
            }
            else {
                $entry.State = 'Ready'
            }

            $entry.Detail = ($issues -join '; ')
            $results += [pscustomobject]$entry
        }
    }

    return $results
}

function Get-RecentDlpMatches {
    param(
        [Parameter(Mandatory)] [PSCustomObject]$Config,
        [int]$HoursBack = 24
    )

    if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
        return $null
    }

    $end = Get-Date
    $start = $end.AddHours(-$HoursBack)
    $prefix = [string]$Config.prefix

    try {
        $records = Search-UnifiedAuditLog `
            -StartDate $start `
            -EndDate $end `
            -RecordType ComplianceDLPExchange, ComplianceDLPSharePoint `
            -ResultSize 50 `
            -ErrorAction Stop
    }
    catch {
        Write-LabLog -Message "Audit search failed: $($_.Exception.Message)" -Level Warning
        return $null
    }

    $matchRecords = @()
    foreach ($r in @($records)) {
        $data = $r.AuditData | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $data) { continue }
        $policyMatch = [string]$data.PolicyDetails.PolicyName
        if ($policyMatch -and $policyMatch -like "$prefix-*") {
            $matchRecords += [pscustomobject]@{
                Time   = [datetime]$r.CreationDate
                Policy = $policyMatch
                User   = [string]$data.UserId
                Record = [string]$r.RecordType
            }
        }
    }

    return $matchRecords
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

# --- main ---

$resolvedPath = Resolve-LabConfigPath -ExplicitConfigPath $ConfigPath -ProfileName $LabProfile -CloudEnv $Cloud
Write-LabLog -Message "Loading config: $resolvedPath" -Level Info
$config = Get-Content -Path $resolvedPath -Raw | ConvertFrom-Json

if (-not $config.workloads.dlp -or -not $config.workloads.dlp.enabled) {
    Write-LabLog -Message 'DLP workload not enabled in config; nothing to check.' -Level Warning
    return
}

Connect-CompliancePowerShell -Tenant $TenantId

$now = Get-Date
$policyResults = Get-PolicyReadiness -Config $config -Now $now
$ruleResults = Get-RuleReadiness -Config $config

Write-Section 'Policy readiness'
$policyResults |
    Format-Table -AutoSize Policy, Exists, Mode, Enabled, State, LastModified, AlertETA, Detail |
    Out-String -Width 4096 |
    Write-Host

Write-Section 'Rule readiness'
foreach ($r in $ruleResults) {
    $color = if ($r.State -eq 'Ready') { 'Green' }
             elseif ($r.State -eq 'Warn') { 'Yellow' }
             else { 'Red' }
    Write-Host ("[{0}] {1}" -f $r.State, $r.Rule) -ForegroundColor $color
    Write-Host ("    Policy        : {0}" -f $r.Policy)
    Write-Host ("    Exists        : {0}" -f $r.Exists)
    Write-Host ("    Disabled      : {0}" -f $r.Disabled)
    Write-Host ("    Mode          : {0}" -f $r.Mode)
    Write-Host ("    BlockAccess   : {0}" -f $r.BlockAccess)
    Write-Host ("    ReportSeverity: {0}" -f $r.ReportSeverity)
    Write-Host ("    GenerateAlert : {0}" -f $r.GenerateAlert)
    Write-Host ("    AlertHasSmtp  : {0}" -f $r.AlertHasSmtp)
    Write-Host ("    NotifyUser    : {0}" -f $r.NotifyUser)
    Write-Host ("    IncidentReport: {0}" -f $r.IncidentReport)
    if ($r.Detail) { Write-Host ("    Detail        : {0}" -f $r.Detail) -ForegroundColor DarkYellow }
}

if (-not $SkipAuditQuery.IsPresent) {
    Write-Section 'Recent DLP rule matches (last 24h, audit log)'
    $dlpMatches = Get-RecentDlpMatches -Config $config -HoursBack 24
    if ($null -eq $dlpMatches) {
        Write-Host 'Audit search unavailable in this session. Skipping.' -ForegroundColor Yellow
    }
    elseif ($dlpMatches.Count -eq 0) {
        Write-Host 'No matches found in last 24h. Generate test activity (send email / upload file with matching SIT).' -ForegroundColor Yellow
    }
    else {
        $dlpMatches | Sort-Object Time -Descending | Format-Table -AutoSize Time, Policy, User, Record
    }
}

Write-Section 'Verdict'
$blockedPolicies = @($policyResults | Where-Object { $_.State -eq 'Blocked' })
$waitingPolicies = @($policyResults | Where-Object { $_.State -eq 'Wait' })
$blockedRules    = @($ruleResults   | Where-Object { $_.State -eq 'Blocked' })
$warnRules       = @($ruleResults   | Where-Object { $_.State -eq 'Warn' })

if ($blockedPolicies.Count -gt 0 -or $blockedRules.Count -gt 0) {
    Write-Host "BLOCKED: $($blockedPolicies.Count) policy, $($blockedRules.Count) rule issue(s). Fix before expecting alerts." -ForegroundColor Red
}
elseif ($waitingPolicies.Count -gt 0) {
    $earliest = ($waitingPolicies | Sort-Object AlertETA | Select-Object -First 1).AlertETA
    $etaText = $earliest.ToString('yyyy-MM-dd HH:mm')
    Write-Host "WAIT: Alert surface window closes ~$etaText. Re-check then." -ForegroundColor Yellow
}
elseif ($warnRules.Count -gt 0) {
    Write-Host "READY (with warnings): $($warnRules.Count) rule(s) have soft issues that may reduce alert reliability." -ForegroundColor Yellow
}
else {
    Write-Host 'READY. Policies are past the alert window and configured for alerting. Generate test activity if no matches yet.' -ForegroundColor Green
}

Write-Section 'Where to look for alerts'
Write-Host 'Defender XDR (recommended, 6-month retention): https://security.microsoft.com/alerts  (filter ServiceSource = Data Loss Prevention)'
Write-Host 'DLP alerts dashboard (30-day retention):       https://purview.microsoft.com/datalossprevention/alerts'
Write-Host 'Activity explorer (matches, user overrides):   https://purview.microsoft.com/datagovernance/activityexplorer'
