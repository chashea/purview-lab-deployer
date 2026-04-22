#Requires -Version 7.0

<#
.SYNOPSIS
    Smoke test for a deployed Purview → Sentinel lab. Validates that the
    workspace, Sentinel onboarding, Content Hub connector cards, analytics
    rules, workbook, playbook, and automation rule all exist and are healthy.

.DESCRIPTION
    Reads the specified lab config, derives the expected resources, queries
    Azure Resource Manager, and prints a per-check PASS/FAIL/WARN table. Exits
    non-zero on any FAIL (suitable for CI).

    Runs read-only. Never modifies anything.

.PARAMETER ConfigPath
    Path to the lab config JSON (e.g. configs/commercial/purview-sentinel-demo.json).

.PARAMETER SubscriptionId
    Override the subscription from config. Optional.

.EXAMPLE
    pwsh ./scripts/Test-SentinelLab.ps1 -ConfigPath ./configs/commercial/purview-sentinel-demo.json

.NOTES
    Requires `az` CLI with an active login (`az login`) and Reader access to
    the workspace resource group.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$ConfigPath,

    [Parameter()]
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'
$script:checks = [System.Collections.Generic.List[pscustomobject]]::new()

function Add-Check {
    param(
        [string]$Name,
        [ValidateSet('PASS', 'FAIL', 'WARN')]
        [string]$Status,
        [string]$Detail = ''
    )
    $script:checks.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
}

function Invoke-Rest {
    param([string]$Url)
    try {
        $raw = & az rest --method GET --url $Url --only-show-errors 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw $raw }
        return $raw | ConvertFrom-Json -Depth 50
    }
    catch {
        return $null
    }
}

$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
$s = $config.workloads.sentinelIntegration
if (-not $s -or -not $s.enabled) {
    Write-Error "Config does not have workloads.sentinelIntegration.enabled=true"
    exit 2
}

$sub   = if ($SubscriptionId) { $SubscriptionId } else { [string]$s.subscriptionId }
$rg    = [string]$s.resourceGroup.name
$ws    = [string]$s.workspace.name
$prefix = [string]$config.prefix
$wsId  = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws"
$arm   = 'https://management.azure.com'

Write-Host ""
Write-Host "== Purview → Sentinel lab smoke test ==" -ForegroundColor Cyan
Write-Host "  sub=$sub" -ForegroundColor DarkGray
Write-Host "  rg =$rg" -ForegroundColor DarkGray
Write-Host "  ws =$ws" -ForegroundColor DarkGray
Write-Host ""

# 1. Workspace exists
$wsResp = Invoke-Rest "$arm$wsId`?api-version=2022-10-01"
if ($wsResp -and $wsResp.id) { Add-Check -Name 'Workspace exists' -Status 'PASS' -Detail "sku=$($wsResp.properties.sku.name)" }
else                         { Add-Check -Name 'Workspace exists' -Status 'FAIL' -Detail 'not found' }

# 2. Sentinel onboarded
$onb = Invoke-Rest "$arm$wsId/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2023-11-01"
if ($onb -and $onb.id) { Add-Check -Name 'Sentinel onboarded' -Status 'PASS' }
else                   { Add-Check -Name 'Sentinel onboarded' -Status 'FAIL' -Detail 'no onboardingStates/default' }

# 3. Expected connectors from config
$expectedConnectors = @()
if ($s.PSObject.Properties['connectors']) {
    if ($s.connectors.PSObject.Properties['office365']              -and [bool]$s.connectors.office365.enabled)              { $expectedConnectors += 'Office 365' }
    if ($s.connectors.PSObject.Properties['microsoftDefenderXdr']   -and [bool]$s.connectors.microsoftDefenderXdr.enabled)   { $expectedConnectors += 'Microsoft Defender XDR' }
    if ($s.connectors.PSObject.Properties['insiderRiskManagement']  -and [bool]$s.connectors.insiderRiskManagement.enabled)  { $expectedConnectors += 'Microsoft 365 Insider Risk Management' }
}

$dc = Invoke-Rest "$arm$wsId/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2023-11-01"
$tmpl = Invoke-Rest "$arm$wsId/providers/Microsoft.SecurityInsights/contentTemplates?api-version=2024-09-01"
$dcItems   = if ($dc   -and $dc.value)   { @($dc.value) } else { @() }
$tmplNames = if ($tmpl -and $tmpl.value) { @($tmpl.value | Where-Object { $_.properties.contentKind -eq 'DataConnector' } | ForEach-Object { [string]$_.properties.displayName }) } else { @() }

# Map expected display names to dataConnector 'kind' values as a null-title fallback.
# Per MS Learn Microsoft.SecurityInsights/dataConnectors (2025-07-01-preview):
#   - Office 365 activity → kind: Office365
#   - Microsoft Defender XDR → kind: MicrosoftThreatProtection
#   - Microsoft 365 Insider Risk Management → kind: OfficeIRM
$kindAliases = @{
    'Office 365'                                = @('Office365')
    'Microsoft Defender XDR'                    = @('MicrosoftThreatProtection','Microsoft365Defender')
    'Microsoft 365 Insider Risk Management'     = @('OfficeIRM')
}

foreach ($expected in $expectedConnectors) {
    $inDc = $false
    foreach ($d in $dcItems) {
        $title = [string]$d.properties.connectorUiConfig.title
        if ($title -like "*$expected*") { $inDc = $true; break }
        if ($kindAliases.ContainsKey($expected) -and ($kindAliases[$expected] -contains [string]$d.kind)) { $inDc = $true; break }
    }
    $inTmpl = ($tmplNames | Where-Object { $_ -like "*$expected*" }).Count -gt 0
    if ($inDc)        { Add-Check -Name "Connector: $expected"      -Status 'PASS' -Detail 'live in /dataConnectors' }
    elseif ($inTmpl)  { Add-Check -Name "Connector: $expected"      -Status 'PASS' -Detail 'installed via Content Hub (pending user consent)' }
    else              { Add-Check -Name "Connector: $expected"      -Status 'FAIL' -Detail 'not found in /dataConnectors or /contentTemplates' }
}

# 4. Analytics rules
$rulesResp = Invoke-Rest "$arm$wsId/providers/Microsoft.SecurityInsights/alertRules?api-version=2023-11-01"
$ruleByName = @{}
if ($rulesResp -and $rulesResp.value) {
    foreach ($r in $rulesResp.value) { $ruleByName[[string]$r.properties.displayName] = $r }
}
if ($s.PSObject.Properties['analyticsRules']) {
    foreach ($r in @($s.analyticsRules)) {
        $expectedName = "$prefix-$($r.name)"
        if ($ruleByName.ContainsKey($expectedName)) {
            $rule = $ruleByName[$expectedName]
            $hasEntities = $rule.properties.entityMappings -and ($rule.properties.entityMappings).Count -gt 0
            if ($hasEntities) { Add-Check -Name "Rule: $expectedName" -Status 'PASS' -Detail "entity-mapped ($($rule.properties.entityMappings.Count))" }
            else              { Add-Check -Name "Rule: $expectedName" -Status 'WARN' -Detail 'deployed but no entity mappings' }
        }
        else {
            Add-Check -Name "Rule: $expectedName" -Status 'FAIL' -Detail 'not found'
        }
    }
}

# 5. Workbook
if ($s.PSObject.Properties['workbook'] -and [bool]$s.workbook.enabled) {
    # Support both single {name,...} and multi-workbook {workbooks:[{name,asset}, ...]} configs
    $wbEntries = if ($s.workbook.PSObject.Properties['workbooks'] -and @($s.workbook.workbooks).Count -gt 0) {
        @($s.workbook.workbooks)
    }
    else {
        @([pscustomobject]@{ name = [string]$s.workbook.name })
    }

    $wbResp = Invoke-Rest "$arm/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Insights/workbooks?api-version=2023-06-01&category=sentinel"
    $deployedNames = @()
    if ($wbResp -and $wbResp.value) {
        $deployedNames = @($wbResp.value | ForEach-Object { [string]$_.properties.displayName })
    }

    foreach ($wbEntry in $wbEntries) {
        $wbDisplayName = "$prefix-$($wbEntry.name)"
        if ($deployedNames -contains $wbDisplayName) {
            Add-Check -Name "Workbook: $wbDisplayName" -Status 'PASS'
        }
        else {
            Add-Check -Name "Workbook: $wbDisplayName" -Status 'FAIL' -Detail 'not found'
        }
    }
}

# 6. Playbook + automation rule
if ($s.PSObject.Properties['playbooks'] -and $s.playbooks -and
    $s.playbooks.PSObject.Properties['irmAutoTriage'] -and [bool]$s.playbooks.irmAutoTriage.enabled) {
    $pbName = "$prefix-IRM-AutoTriage"
    $pbResp = Invoke-Rest "$arm/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$pbName`?api-version=2019-05-01"
    if ($pbResp -and $pbResp.id) {
        $state = [string]$pbResp.properties.state
        if ($state -eq 'Enabled') { Add-Check -Name "Playbook: $pbName" -Status 'PASS' -Detail "state=$state" }
        else                      { Add-Check -Name "Playbook: $pbName" -Status 'WARN' -Detail "state=$state" }
    }
    else {
        Add-Check -Name "Playbook: $pbName" -Status 'FAIL' -Detail 'not found'
    }

    $arName = "$prefix-IRM-AutoTriage"
    $arResp = Invoke-Rest "$arm$wsId/providers/Microsoft.SecurityInsights/automationRules?api-version=2023-11-01"
    $arFound = $false
    if ($arResp -and $arResp.value) {
        $arFound = ($arResp.value | Where-Object { [string]$_.properties.displayName -eq $arName }).Count -gt 0
    }
    if ($arFound) { Add-Check -Name "Automation rule: $arName" -Status 'PASS' }
    else          { Add-Check -Name "Automation rule: $arName" -Status 'FAIL' -Detail 'not found' }
}

# 7. Data-flow check: at least one SecurityAlert row or OfficeActivity row in
#    the last 24h proves connectors are actually producing data. Without this
#    check, a deploy can pass all structural tests yet be silently dead.
try {
    $wsForQuery = Invoke-Rest "$arm/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$($s.workspace.name)?api-version=2022-10-01"
    $customerId = [string]$wsForQuery.properties.customerId
    if ([string]::IsNullOrWhiteSpace($customerId)) {
        Add-Check -Name 'Data flow (24h)' -Status 'WARN' -Detail 'workspace customerId not available yet'
    }
    else {
        $query = 'union isfuzzy=true SecurityAlert, OfficeActivity | where TimeGenerated > ago(24h) | summarize rows=count()'
        $escaped = [uri]::EscapeDataString($query)
        $queryResp = Invoke-Rest "https://api.loganalytics.io/v1/workspaces/$customerId/query?query=$escaped"
        $rowCount = 0
        if ($queryResp -and $queryResp.tables -and $queryResp.tables[0].rows) {
            $rowCount = [int]$queryResp.tables[0].rows[0][0]
        }
        if ($rowCount -gt 0) {
            Add-Check -Name 'Data flow (24h)' -Status 'PASS' -Detail "$rowCount row(s) in SecurityAlert/OfficeActivity"
        }
        else {
            Add-Check -Name 'Data flow (24h)' -Status 'WARN' -Detail 'no rows yet — confirm Defender XDR consent and IRM SIEM export; allow 60 min after first deploy'
        }
    }
}
catch {
    Add-Check -Name 'Data flow (24h)' -Status 'WARN' -Detail "query failed: $($_.Exception.Message)"
}

# Render
$script:checks | Format-Table -AutoSize | Out-String | Write-Host

$pass = @($script:checks | Where-Object { $_.Status -eq 'PASS' }).Count
$fail = @($script:checks | Where-Object { $_.Status -eq 'FAIL' }).Count
$warn = @($script:checks | Where-Object { $_.Status -eq 'WARN' }).Count

Write-Host "Summary: PASS=$pass  WARN=$warn  FAIL=$fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ""

if ($fail -gt 0) { exit 1 } else { exit 0 }
