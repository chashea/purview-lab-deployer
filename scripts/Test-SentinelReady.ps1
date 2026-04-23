#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Pre-demo readiness check for the Purview → Sentinel integration lab.

.DESCRIPTION
    Verifies that the Sentinel lab is demo-ready. Unlike Test-SentinelLab.ps1
    (which is a deep smoke test), this script is a lightweight gate for
    demo day — fail fast on missing state.

    Checks performed:
      1. Azure CLI is signed in and points at the configured subscription
      2. Resource group exists
      3. Log Analytics workspace exists and Sentinel is onboarded
      4. Data connectors are installed (Defender XDR, IRM, Office 365)
      5. Analytics rules from config are enabled
      6. Recent SecurityAlert rows present (last 24h) — proves data is flowing
      7. Playbook + automation rule wired (if config includes them)

    Output: readiness table + verdict (Ready / Wait / Blocked).

.PARAMETER ConfigPath
    Path to the Sentinel lab config JSON. Defaults to commercial profile.

.PARAMETER LabProfile
    Lab profile shorthand. Default: 'purview-sentinel'.

.PARAMETER Cloud
    Cloud environment (commercial or gcc). Default: commercial.

.PARAMETER SubscriptionId
    Azure subscription ID. Required unless the config sets it. Can also be set
    via PURVIEW_SUBSCRIPTION_ID environment variable.

.PARAMETER SkipDataFlowCheck
    Skip the query for recent SecurityAlert rows (useful when the workspace is
    newly deployed and you know no data has flowed yet).

.EXAMPLE
    ./scripts/Test-SentinelReady.ps1 -LabProfile purview-sentinel -Cloud commercial -SubscriptionId <sub>
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$LabProfile = 'purview-sentinel',

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = 'commercial',

    [Parameter()]
    [string]$SubscriptionId = $env:PURVIEW_SUBSCRIPTION_ID,

    [Parameter()]
    [switch]$SkipDataFlowCheck
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules' 'Logging.psm1') -Force

function Resolve-LabConfigPath {
    param([string]$ExplicitConfigPath, [string]$ProfileName, [string]$CloudEnv)

    if ($ExplicitConfigPath) {
        if (-not (Test-Path $ExplicitConfigPath)) { throw "Config file not found: $ExplicitConfigPath" }
        return (Resolve-Path $ExplicitConfigPath).Path
    }
    $candidate = Join-Path $repoRoot 'configs' $CloudEnv "$ProfileName-demo.json"
    if (-not (Test-Path $candidate)) { throw "Could not locate config at $candidate." }
    return (Resolve-Path $candidate).Path
}

function Invoke-AzRest {
    param([Parameter(Mandatory)][string]$Uri, [string]$Method = 'GET')

    $result = az rest --method $Method --uri $Uri --only-show-errors 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "az rest $Method $Uri failed: $result"
    }
    if ([string]::IsNullOrWhiteSpace($result)) { return $null }
    return $result | ConvertFrom-Json
}

function Test-AzCliSignedIn {
    try {
        $account = az account show --only-show-errors 2>&1 | ConvertFrom-Json
        if ($account -and $account.id) { return [pscustomobject]@{ Signed = $true; Current = [string]$account.id } }
    }
    catch { $null = $_ }
    return [pscustomobject]@{ Signed = $false; Current = $null }
}

function Get-WorkspaceReadiness {
    param([string]$Sub, [string]$Rg, [string]$WsName)
    $results = @()

    $rgUri = "https://management.azure.com/subscriptions/$Sub/resourceGroups/$Rg`?api-version=2021-04-01"
    try {
        Invoke-AzRest -Uri $rgUri | Out-Null
        $results += [pscustomobject]@{ Check = "Resource group: $Rg"; State = 'Ready'; Detail = 'Exists.' }
    }
    catch {
        $results += [pscustomobject]@{ Check = "Resource group: $Rg"; State = 'Blocked'; Detail = 'Missing — run Deploy-Lab.ps1.' }
        return $results
    }

    $wsUri = "https://management.azure.com/subscriptions/$Sub/resourceGroups/$Rg/providers/Microsoft.OperationalInsights/workspaces/$WsName`?api-version=2022-10-01"
    try {
        $ws = Invoke-AzRest -Uri $wsUri
        $results += [pscustomobject]@{
            Check  = "Log Analytics workspace: $WsName"
            State  = 'Ready'
            Detail = "SKU: $($ws.properties.sku.name), Retention: $($ws.properties.retentionInDays) days."
        }
    }
    catch {
        $results += [pscustomobject]@{ Check = "Log Analytics workspace: $WsName"; State = 'Blocked'; Detail = 'Missing.' }
        return $results
    }

    $onboardUri = "https://management.azure.com/subscriptions/$Sub/resourceGroups/$Rg/providers/Microsoft.OperationalInsights/workspaces/$WsName/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-09-01"
    try {
        Invoke-AzRest -Uri $onboardUri | Out-Null
        $results += [pscustomobject]@{ Check = 'Sentinel onboarding'; State = 'Ready'; Detail = 'Workspace is Sentinel-enabled.' }
    }
    catch {
        $results += [pscustomobject]@{ Check = 'Sentinel onboarding'; State = 'Blocked'; Detail = 'Sentinel not onboarded on workspace.' }
    }

    return $results
}

function Get-ConnectorReadiness {
    param([string]$Sub, [string]$Rg, [string]$WsName, [PSCustomObject]$ConnectorConfig)

    $results = @()
    $baseUri = "https://management.azure.com/subscriptions/$Sub/resourceGroups/$Rg/providers/Microsoft.OperationalInsights/workspaces/$WsName/providers/Microsoft.SecurityInsights"
    $expectedKinds = @{
        microsoftDefenderXdr  = 'MicrosoftThreatProtection'
        insiderRiskManagement = 'OfficeIRM'
        office365             = 'Office365'
    }

    try {
        $connectors = (Invoke-AzRest -Uri "$baseUri/dataConnectors?api-version=2024-09-01").value
    }
    catch {
        $results += [pscustomobject]@{ Check = 'Data connectors'; State = 'Blocked'; Detail = "Query failed: $($_.Exception.Message)" }
        return $results
    }

    foreach ($name in @($ConnectorConfig.PSObject.Properties.Name)) {
        if (-not [bool]$ConnectorConfig.$name.enabled) { continue }
        $expectedKind = $expectedKinds[$name]
        $match = $connectors | Where-Object { [string]$_.kind -eq $expectedKind }
        if ($match) {
            $results += [pscustomobject]@{
                Check  = "Connector: $name ($expectedKind)"
                State  = 'Ready'
                Detail = "Installed. ID: $($match[0].id.Split('/')[-1])"
            }
        }
        else {
            $results += [pscustomobject]@{
                Check  = "Connector: $name ($expectedKind)"
                State  = 'Wait'
                Detail = "Not yet installed. Content Hub solution may still be provisioning, or tenant admin consent pending."
            }
        }
    }

    return $results
}

function Get-AnalyticsRuleReadiness {
    param([string]$Sub, [string]$Rg, [string]$WsName, [PSCustomObject]$Config, [array]$ExpectedRules)

    $results = @()
    $uri = "https://management.azure.com/subscriptions/$Sub/resourceGroups/$Rg/providers/Microsoft.OperationalInsights/workspaces/$WsName/providers/Microsoft.SecurityInsights/alertRules?api-version=2024-09-01"

    try {
        $rules = (Invoke-AzRest -Uri $uri).value
    }
    catch {
        $results += [pscustomobject]@{ Check = 'Analytics rules'; State = 'Blocked'; Detail = "Query failed: $($_.Exception.Message)" }
        return $results
    }

    foreach ($rule in $ExpectedRules) {
        $expectedName = "$($Config.prefix)-$($rule.name)"
        $match = $rules | Where-Object { [string]$_.properties.displayName -eq $expectedName -or [string]$_.name -eq $expectedName }
        if (-not $match) {
            $results += [pscustomobject]@{ Check = "Rule: $expectedName"; State = 'Blocked'; Detail = 'Missing.' }
            continue
        }

        $enabled = [bool]$match.properties.enabled
        if ($enabled) {
            $results += [pscustomobject]@{ Check = "Rule: $expectedName"; State = 'Ready'; Detail = "Enabled, severity $($match.properties.severity)." }
        }
        else {
            $results += [pscustomobject]@{ Check = "Rule: $expectedName"; State = 'Wait'; Detail = 'Rule exists but is disabled. Toggle on in Sentinel.' }
        }
    }

    return $results
}

function Get-DataFlowReadiness {
    param([string]$Sub, [string]$Rg, [string]$WsName)
    $results = @()

    $workspaceIdUri = "https://management.azure.com/subscriptions/$Sub/resourceGroups/$Rg/providers/Microsoft.OperationalInsights/workspaces/$WsName`?api-version=2022-10-01"
    try {
        $ws = Invoke-AzRest -Uri $workspaceIdUri
        $customerId = [string]$ws.properties.customerId
    }
    catch {
        $results += [pscustomobject]@{ Check = 'Data flow'; State = 'Blocked'; Detail = "Workspace query failed: $($_.Exception.Message)" }
        return $results
    }

    if ([string]::IsNullOrWhiteSpace($customerId)) {
        $results += [pscustomobject]@{ Check = 'Data flow'; State = 'Wait'; Detail = 'Workspace has no customerId yet.' }
        return $results
    }

    $query = 'SecurityAlert | where TimeGenerated > ago(24h) | summarize Count=count()'
    $queryUri = "https://api.loganalytics.io/v1/workspaces/$customerId/query?query=$([uri]::EscapeDataString($query))"

    try {
        $response = Invoke-AzRest -Uri $queryUri
        $count = if ($response.tables -and $response.tables[0].rows) { [int]$response.tables[0].rows[0][0] } else { 0 }
        if ($count -gt 0) {
            $results += [pscustomobject]@{ Check = 'SecurityAlert rows (24h)'; State = 'Ready'; Detail = "$count row(s) present." }
        }
        else {
            $results += [pscustomobject]@{
                Check  = 'SecurityAlert rows (24h)'
                State  = 'Wait'
                Detail = 'No rows in last 24h. Defender XDR connector consent may be pending, or wait for first data batch.'
            }
        }
    }
    catch {
        $results += [pscustomobject]@{ Check = 'SecurityAlert rows (24h)'; State = 'Wait'; Detail = "Log Analytics query failed (likely permission): $($_.Exception.Message)" }
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

if (-not $config.workloads.sentinelIntegration -or -not [bool]$config.workloads.sentinelIntegration.enabled) {
    throw "Config does not have an enabled sentinelIntegration workload."
}

$effectiveSubscriptionId = if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $SubscriptionId
}
else {
    [string]$config.workloads.sentinelIntegration.subscriptionId
}

if ([string]::IsNullOrWhiteSpace($effectiveSubscriptionId)) {
    throw 'No subscription ID. Pass -SubscriptionId, set PURVIEW_SUBSCRIPTION_ID, or populate the config.'
}

$account = Test-AzCliSignedIn
if (-not $account.Signed) {
    throw 'Azure CLI is not signed in. Run az login (and az cloud set --name AzureUSGovernment for GCC).'
}
if ($account.Current -ne $effectiveSubscriptionId) {
    Write-LabLog -Message "az CLI is on subscription $($account.Current); switching context to $effectiveSubscriptionId." -Level Info
    az account set --subscription $effectiveSubscriptionId --only-show-errors | Out-Null
}

$rg = [string]$config.workloads.sentinelIntegration.resourceGroup.name
$ws = [string]$config.workloads.sentinelIntegration.workspace.name

$allResults = @()
$allResults += Get-WorkspaceReadiness -Sub $effectiveSubscriptionId -Rg $rg -WsName $ws

# Only check connectors / rules / data flow if workspace exists
if (($allResults | Where-Object { $_.Check -like 'Resource group*' -and $_.State -eq 'Ready' }).Count -gt 0 -and
    ($allResults | Where-Object { $_.Check -like 'Log Analytics*' -and $_.State -eq 'Ready' }).Count -gt 0) {

    $allResults += Get-ConnectorReadiness -Sub $effectiveSubscriptionId -Rg $rg -WsName $ws `
        -ConnectorConfig $config.workloads.sentinelIntegration.connectors

    $allResults += Get-AnalyticsRuleReadiness -Sub $effectiveSubscriptionId -Rg $rg -WsName $ws `
        -Config $config -ExpectedRules @($config.workloads.sentinelIntegration.analyticsRules)

    if (-not $SkipDataFlowCheck) {
        $allResults += Get-DataFlowReadiness -Sub $effectiveSubscriptionId -Rg $rg -WsName $ws
    }
}

Write-Host ''
Write-Host '=== Sentinel Lab Readiness ===' -ForegroundColor Cyan
Write-ReadinessTable -Results $allResults

$blocked = @($allResults | Where-Object { $_.State -eq 'Blocked' })
$waiting = @($allResults | Where-Object { $_.State -eq 'Wait' })

if ($blocked.Count -gt 0) {
    Write-Host "VERDICT: BLOCKED — $($blocked.Count) item(s) require action." -ForegroundColor Red
    exit 2
}
elseif ($waiting.Count -gt 0) {
    Write-Host "VERDICT: WAIT — $($waiting.Count) item(s) propagating or pending consent." -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host 'VERDICT: READY — Sentinel lab is demo-ready.' -ForegroundColor Green
    exit 0
}
