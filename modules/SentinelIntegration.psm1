#Requires -Version 7.0

<#
.SYNOPSIS
    Microsoft Sentinel integration workload for purview-lab-deployer.

.DESCRIPTION
    Provisions an Azure Log Analytics workspace, onboards Microsoft Sentinel,
    deploys data connectors that surface Microsoft Purview signals (DLP alerts
    via Defender XDR, Insider Risk Management alerts via the Purview IRM
    connector, optional Office 365 audit for OfficeActivity), plus analytics
    rules and a workbook.

    Implementation notes:
      * Uses ARM REST via `az rest --method PUT` as the primary control plane.
        The `az sentinel` CLI data-connector surface is preview/experimental
        and ships outdated connector kinds; we avoid it for mutations.
      * `-WhatIf` / `-SkipAuth` preserves the existing dry-run contract: no
        `az login` required and zero mutating `az rest` calls.
      * Teardown is safety-gated. Resource group deletion requires all of:
        - `-ForceDeleteResourceGroup` switch at call time
        - a manifest
        - manifest.createdResourceGroup == true
        - RG tags include `createdBy=purview-lab-deployer`
        - exact name + subscription match
#>

$script:SentinelTag = 'purview-lab-deployer'

function Get-SentinelAssetPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$RelativePath
    )

    $root = Join-Path $PSScriptRoot 'assets' 'sentinel' 'arm'
    return (Join-Path $root (Join-Path @($RelativePath) -ChildPath ''))
}

function Read-SentinelAsset {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Sentinel ARM asset not found: $Path"
    }
    return Get-Content -Path $Path -Raw
}

function Expand-SentinelTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Template,

        [Parameter(Mandatory)]
        [hashtable]$Tokens
    )

    $out = $Template
    foreach ($key in $Tokens.Keys) {
        $value = [string]$Tokens[$key]
        $out = $out.Replace("{{${key}}}", $value)
    }
    return $out
}

function Test-SentinelWhatIf {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return [bool]$WhatIfPreference
}

function Invoke-SentinelAzRest {
    <#
    .SYNOPSIS
        Invokes `az rest` for a PUT/DELETE/GET operation against ARM.
        Never invoked in WhatIf mode — the caller is expected to gate.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'PUT', 'DELETE', 'POST', 'PATCH')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter()]
        [string]$Body,

        [Parameter()]
        [switch]$AllowMissing
    )

    $azArgs = @('rest', '--method', $Method.ToLowerInvariant(), '--url', $Url, '--only-show-errors')
    $tempBodyFile = $null
    if ($PSBoundParameters.ContainsKey('Body') -and -not [string]::IsNullOrEmpty($Body)) {
        $tempBodyFile = New-TemporaryFile
        Set-Content -Path $tempBodyFile -Value $Body -Encoding utf8
        $azArgs += @('--body', "@$($tempBodyFile.FullName)", '--headers', 'Content-Type=application/json')
    }

    try {
        $raw = & az @azArgs 2>&1
        $exit = $LASTEXITCODE

        if ($exit -ne 0) {
            $combined = ($raw | Out-String)
            if ($AllowMissing -and ($combined -match 'ResourceNotFound' -or $combined -match 'NotFound' -or $combined -match '404')) {
                return $null
            }
            throw "az rest $Method $Url failed (exit $exit): $combined"
        }

        if ($raw -and ($raw | Out-String).Trim().Length -gt 0) {
            try {
                return ($raw | Out-String) | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                return ($raw | Out-String)
            }
        }
        return $null
    }
    finally {
        if ($tempBodyFile -and (Test-Path $tempBodyFile)) {
            Remove-Item $tempBodyFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SentinelScope {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $s = $Config.workloads.sentinelIntegration
    if (-not $s) { throw 'sentinelIntegration workload config is missing.' }
    if ([string]::IsNullOrWhiteSpace($s.subscriptionId)) { throw 'sentinelIntegration.subscriptionId is required.' }
    if (-not $s.resourceGroup -or [string]::IsNullOrWhiteSpace($s.resourceGroup.name) -or [string]::IsNullOrWhiteSpace($s.resourceGroup.location)) {
        throw 'sentinelIntegration.resourceGroup.name and .location are required.'
    }
    if (-not $s.workspace -or [string]::IsNullOrWhiteSpace($s.workspace.name)) {
        throw 'sentinelIntegration.workspace.name is required.'
    }

    $retention = 30
    if ($s.workspace.PSObject.Properties['retentionDays'] -and $s.workspace.retentionDays) {
        $retention = [int]$s.workspace.retentionDays
    }
    $sku = 'PerGB2018'
    if ($s.workspace.PSObject.Properties['sku'] -and -not [string]::IsNullOrWhiteSpace([string]$s.workspace.sku)) {
        $sku = [string]$s.workspace.sku
    }

    return @{
        SubscriptionId      = [string]$s.subscriptionId
        ResourceGroup       = [string]$s.resourceGroup.name
        Location            = [string]$s.resourceGroup.location
        WorkspaceName       = [string]$s.workspace.name
        RetentionDays       = $retention
        Sku                 = $sku
        WorkspaceResourceId = "/subscriptions/$($s.subscriptionId)/resourceGroups/$($s.resourceGroup.name)/providers/Microsoft.OperationalInsights/workspaces/$($s.workspace.name)"
        ArmBase             = 'https://management.azure.com'
    }
}

function Deploy-SentinelResourceGroup {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter(Mandatory)]
        [string]$LabPrefix
    )

    $url = "$($Scope.ArmBase)/subscriptions/$($Scope.SubscriptionId)/resourcegroups/$($Scope.ResourceGroup)?api-version=2021-04-01"

    if (Test-SentinelWhatIf) {
        Write-LabLog -Message "[WhatIf] Would ensure resource group '$($Scope.ResourceGroup)' in '$($Scope.Location)'." -Level Info
        return @{ id = "<planned-rg:$($Scope.ResourceGroup)>"; created = $false; preexisting = $null }
    }

    $existing = Invoke-SentinelAzRest -Method GET -Url $url -AllowMissing
    if ($existing -and $existing.id) {
        Write-LabLog -Message "Resource group '$($Scope.ResourceGroup)' already exists." -Level Info
        return @{ id = [string]$existing.id; created = $false; preexisting = $true }
    }

    $body = @{
        location = $Scope.Location
        tags     = @{
            createdBy = $script:SentinelTag
            labPrefix = $LabPrefix
        }
    } | ConvertTo-Json -Depth 4

    $result = Invoke-SentinelAzRest -Method PUT -Url $url -Body $body
    Write-LabLog -Message "Created resource group '$($Scope.ResourceGroup)' in '$($Scope.Location)'." -Level Success
    return @{ id = [string]$result.id; created = $true; preexisting = $false }
}

function Deploy-SentinelWorkspace {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter(Mandatory)]
        [string]$LabPrefix
    )

    $url = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)?api-version=2022-10-01"

    $template = Read-SentinelAsset -Path (Join-Path $PSScriptRoot 'assets' 'sentinel' 'arm' 'workspace.json')
    $body = Expand-SentinelTemplate -Template $template -Tokens @{
        location      = $Scope.Location
        sku           = $Scope.Sku
        retentionDays = $Scope.RetentionDays
        labPrefix     = $LabPrefix
    }

    if (Test-SentinelWhatIf) {
        Write-LabLog -Message "[WhatIf] Would PUT Log Analytics workspace '$($Scope.WorkspaceName)'." -Level Info
        return @{ id = "<planned-ws:$($Scope.WorkspaceName)>" }
    }

    $result = Invoke-SentinelAzRest -Method PUT -Url $url -Body $body
    Write-LabLog -Message "Workspace '$($Scope.WorkspaceName)' provisioned (sku=$($Scope.Sku), retention=$($Scope.RetentionDays)d)." -Level Success
    return @{ id = [string]$result.id }
}

function Deploy-SentinelOnboarding {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope
    )

    $url = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2023-11-01"
    $body = Read-SentinelAsset -Path (Join-Path $PSScriptRoot 'assets' 'sentinel' 'arm' 'onboarding.json')

    if (Test-SentinelWhatIf) {
        Write-LabLog -Message "[WhatIf] Would onboard Sentinel on workspace '$($Scope.WorkspaceName)'." -Level Info
        return @{ id = '<planned-onboarding>' }
    }

    $result = Invoke-SentinelAzRest -Method PUT -Url $url -Body $body
    Write-LabLog -Message "Sentinel onboarded on workspace '$($Scope.WorkspaceName)'." -Level Success
    return @{ id = [string]$result.id }
}

function Deploy-SentinelConnectors {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter(Mandatory)]
        [PSCustomObject]$ConnectorsConfig,

        [Parameter(Mandatory)]
        [string]$TenantId
    )

    $deployed = [System.Collections.Generic.List[hashtable]]::new()

    $connectorAssetMap = @{
        microsoftDefenderXdr  = 'microsoftDefenderXdr.json'
        insiderRiskManagement = 'insiderRiskManagement.json'
        office365             = 'office365.json'
    }

    # Connectors that require a Content Hub solution to be installed first.
    # Direct PUT to /dataConnectors fails with "kind ... not supported in api-version"
    # because the ARM backend routes these through the solution-install flow.
    # We auto-install the solution; the final "Connect" step still requires a
    # tenant-side consent click in the Sentinel portal (Defender XDR tenant
    # consent, IRM SIEM-export toggle in Purview) which ARM cannot perform.
    $contentHubConnectors = @{
        microsoftDefenderXdr  = @{
            displayName = 'Microsoft Defender XDR'
            solutionDisplayName = 'Microsoft Defender XDR'
            portalHint  = 'Solution + connector card installed. Finish activation: Sentinel portal > Data connectors > Microsoft Defender XDR > Connect (requires tenant admin consent for the M365D API).'
        }
        insiderRiskManagement = @{
            displayName = 'Microsoft Purview Insider Risk Management'
            solutionDisplayName = 'Microsoft Purview Insider Risk Management'
            portalHint  = 'Solution + connector card installed. Finish activation: (1) Purview portal > Insider risk management > Settings > Export alerts (enable SIEM export), (2) Sentinel portal > Data connectors > Microsoft Purview Insider Risk Management > Connect.'
        }
    }

    foreach ($connectorName in $connectorAssetMap.Keys) {
        if (-not $ConnectorsConfig.PSObject.Properties[$connectorName]) { continue }
        $c = $ConnectorsConfig.$connectorName
        if (-not $c -or -not $c.PSObject.Properties['enabled'] -or -not [bool]$c.enabled) {
            Write-LabLog -Message "Connector '$connectorName' is disabled; skipping." -Level Info
            continue
        }

        # Proactively install the Content Hub solution for connectors that need it.
        if ($contentHubConnectors.ContainsKey($connectorName)) {
            $hub = $contentHubConnectors[$connectorName]
            $installed = Install-SentinelContentHubSolution -Scope $Scope -SolutionDisplayName $hub.solutionDisplayName
            if ($installed) {
                Write-LabLog -Message "Content Hub solution '$($hub.solutionDisplayName)' installed. Connector card now visible in Sentinel; tenant admin consent still required to activate data flow." -Level Info
                $deployed.Add(@{ name = "$($Scope.WorkspaceName)-$connectorName"; kind = $connectorName; id = $null; status = 'content-hub-installed-pending-consent'; remediation = $hub.portalHint })
                continue
            }
        }

        $assetFile = $connectorAssetMap[$connectorName]
        $assetPath = Join-Path $PSScriptRoot 'assets' 'sentinel' 'arm' 'connectors' $assetFile
        $template = Read-SentinelAsset -Path $assetPath

        $tokens = @{ tenantId = $TenantId }
        if ($connectorName -eq 'office365') {
            $dataTypes = @()
            if ($c.PSObject.Properties['dataTypes']) { $dataTypes = @($c.dataTypes | ForEach-Object { [string]$_ }) }
            $tokens.exchangeState   = if ($dataTypes -contains 'Exchange')   { 'Enabled' } else { 'Disabled' }
            $tokens.sharePointState = if ($dataTypes -contains 'SharePoint') { 'Enabled' } else { 'Disabled' }
            $tokens.teamsState      = if ($dataTypes -contains 'Teams')      { 'Enabled' } else { 'Disabled' }
        }

        $body = Expand-SentinelTemplate -Template $template -Tokens $tokens
        $connectorId = "$($Scope.WorkspaceName)-$connectorName"
        $url = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/dataConnectors/$connectorId`?api-version=2023-11-01"

        if (Test-SentinelWhatIf) {
            Write-LabLog -Message "[WhatIf] Would PUT data connector '$connectorId'." -Level Info
            $deployed.Add(@{ name = $connectorId; kind = $connectorName; id = "<planned-connector:$connectorId>" })
            continue
        }

        try {
            $result = Invoke-SentinelAzRest -Method PUT -Url $url -Body $body
            Write-LabLog -Message "Deployed data connector '$connectorId'." -Level Success
            $deployed.Add(@{ name = $connectorId; kind = $connectorName; id = [string]$result.id })
        }
        catch {
            $errMsg = $_.Exception.Message
            if ($contentHubConnectors.ContainsKey($connectorName) -and $errMsg -match 'not supported in api-version') {
                $hint = $contentHubConnectors[$connectorName]
                Write-LabLog -Message "Connector '$($hint.displayName)' Content Hub solution is installed but the data-connector activation requires a portal step." -Level Warning
                Write-LabLog -Message "  Remediation: $($hint.portalHint)" -Level Info
                $deployed.Add(@{ name = $connectorId; kind = $connectorName; id = $null; status = 'requires-portal-activation'; remediation = $hint.portalHint })
            }
            else {
                Write-LabLog -Message "Connector '$connectorId' deployment failed: $errMsg" -Level Warning
                $deployed.Add(@{ name = $connectorId; kind = $connectorName; id = $null; error = $errMsg })
            }
        }
    }

    return $deployed.ToArray()
}

function Install-SentinelContentHubSolution {
    <#
    .SYNOPSIS
    Installs a Microsoft Sentinel Content Hub solution by displayName.

    .DESCRIPTION
    This is the same operation the Sentinel portal performs when you click
    "Install" on a Content Hub solution. Three steps:

      1. Locate the package in the catalog (/contentProductPackages) by
         displayName and grab its `contentProductId` plus inline
         `packagedContent` ARM template (only available on the per-package
         GET, not in the list response).
      2. PUT /contentPackages/{contentId} with the package metadata so the
         workspace records the solution as installed.
      3. Submit an ARM deployment of `packagedContent` against the workspace
         resource group. This is what materializes all the inner resources
         (data-connector definitions, analytics rule templates, hunting
         queries, workbooks, playbooks). Without this step the connector
         card never appears in the Data connectors blade.

    Idempotent: ARM deployments are upserts. Re-running against an
    already-installed solution simply re-applies the template.

    Returns $true on success, $false on any failure.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter(Mandatory)]
        [string]$SolutionDisplayName
    )

    if (Test-SentinelWhatIf) {
        Write-LabLog -Message "[WhatIf] Would install Content Hub solution '$SolutionDisplayName'." -Level Info
        return $true
    }

    # Step 1a: list catalog and find the matching package
    $listUrl = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=2024-09-01"
    try {
        $list = Invoke-SentinelAzRest -Method GET -Url $listUrl
    }
    catch {
        Write-LabLog -Message "Failed to query Content Hub catalog for '$SolutionDisplayName': $($_.Exception.Message)" -Level Warning
        return $false
    }

    $match = $null
    foreach ($pkg in @($list.value)) {
        if ($pkg.properties -and [string]$pkg.properties.displayName -eq $SolutionDisplayName) {
            $match = $pkg
            break
        }
    }

    if (-not $match) {
        Write-LabLog -Message "Content Hub solution '$SolutionDisplayName' not found in catalog for this workspace." -Level Warning
        return $false
    }

    $contentId = [string]$match.properties.contentId
    $contentProductId = [string]$match.name
    $version = [string]$match.properties.version

    # Step 1b: GET the specific package to retrieve the packagedContent template
    $detailUrl = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/contentProductPackages/$contentProductId`?api-version=2024-09-01"
    try {
        $detail = Invoke-SentinelAzRest -Method GET -Url $detailUrl
    }
    catch {
        Write-LabLog -Message "Failed to fetch package detail for '$SolutionDisplayName': $($_.Exception.Message)" -Level Warning
        return $false
    }

    $packagedContent = $detail.properties.packagedContent
    if (-not $packagedContent) {
        Write-LabLog -Message "Package '$SolutionDisplayName' is missing packagedContent; cannot install." -Level Warning
        return $false
    }

    # Step 2: register solution as installed
    $installUrl = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/contentPackages/$contentId`?api-version=2024-09-01"
    $installBody = @{ properties = $detail.properties } | ConvertTo-Json -Depth 50
    try {
        $null = Invoke-SentinelAzRest -Method PUT -Url $installUrl -Body $installBody
    }
    catch {
        Write-LabLog -Message "Failed to register Content Hub solution '$SolutionDisplayName': $($_.Exception.Message)" -Level Warning
        return $false
    }

    # Step 3: deploy packagedContent (this is what materializes data connectors,
    # analytics rule templates, hunting queries, workbooks, etc.)
    $deploymentName = ('pvsentinel-content-' + ($contentId -replace '[^a-zA-Z0-9-]', '-'))
    if ($deploymentName.Length -gt 64) { $deploymentName = $deploymentName.Substring(0, 64) }
    $deployUrl = "$($Scope.ArmBase)/subscriptions/$($Scope.SubscriptionId)/resourceGroups/$($Scope.ResourceGroup)/providers/Microsoft.Resources/deployments/$deploymentName`?api-version=2021-04-01"
    $deployBody = @{
        properties = @{
            mode       = 'Incremental'
            template   = $packagedContent
            parameters = @{
                'workspace'          = @{ value = $Scope.WorkspaceName }
                'workspace-location' = @{ value = $Scope.Location }
            }
        }
    } | ConvertTo-Json -Depth 100

    Write-LabLog -Message "Deploying Content Hub solution '$SolutionDisplayName' (version $version, ~$(@($packagedContent.resources).Count) resources)..." -Level Info
    try {
        $null = Invoke-SentinelAzRest -Method PUT -Url $deployUrl -Body $deployBody
        Write-LabLog -Message "Installed Content Hub solution '$SolutionDisplayName' (version $version)." -Level Success
        return $true
    }
    catch {
        Write-LabLog -Message "Failed to deploy Content Hub solution '$SolutionDisplayName': $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Deploy-SentinelAnalyticsRules {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter(Mandatory)]
        [string]$LabPrefix,

        [Parameter()]
        [AllowNull()]
        [object]$Rules
    )

    $deployed = [System.Collections.Generic.List[hashtable]]::new()
    if (-not $Rules) { return $deployed.ToArray() }

    foreach ($rule in @($Rules)) {
        if ($rule.PSObject.Properties['enabled'] -and -not [bool]$rule.enabled) { continue }

        $templateName = [string]$rule.template
        $assetPath = Join-Path $PSScriptRoot 'assets' 'sentinel' 'arm' 'rules' "$templateName.json"
        if (-not (Test-Path $assetPath)) {
            Write-LabLog -Message "Rule template '$templateName' not found at $assetPath; skipping." -Level Warning
            continue
        }

        $severity = if ($rule.PSObject.Properties['severity'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.severity)) { [string]$rule.severity } else { 'Medium' }
        $displayName = "$LabPrefix-$($rule.name)"
        # Deterministic rule GUID derived from displayName so re-runs upsert instead of duplicating.
        $md5 = [System.Security.Cryptography.MD5]::Create()
        try {
            $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("purview-lab-deployer::$displayName"))
        }
        finally {
            $md5.Dispose()
        }
        $ruleId = ([guid]::new($hash)).ToString()

        $template = Read-SentinelAsset -Path $assetPath
        $body = Expand-SentinelTemplate -Template $template -Tokens @{
            displayName = $displayName
            severity    = $severity
        }

        $url = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/alertRules/$ruleId`?api-version=2023-11-01"

        if (Test-SentinelWhatIf) {
            Write-LabLog -Message "[WhatIf] Would PUT analytics rule '$displayName' (template=$templateName)." -Level Info
            $deployed.Add(@{ name = $displayName; template = $templateName; id = "<planned-rule:$displayName>"; ruleId = $ruleId })
            continue
        }

        try {
            $result = Invoke-SentinelAzRest -Method PUT -Url $url -Body $body
            Write-LabLog -Message "Deployed analytics rule '$displayName'." -Level Success
            $deployed.Add(@{ name = $displayName; template = $templateName; id = [string]$result.id; ruleId = $ruleId })
        }
        catch {
            Write-LabLog -Message "Analytics rule '$displayName' failed: $($_.Exception.Message)" -Level Warning
            $deployed.Add(@{ name = $displayName; template = $templateName; id = $null; ruleId = $ruleId; error = $_.Exception.Message })
        }
    }

    return $deployed.ToArray()
}

function Deploy-SentinelWorkbook {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter(Mandatory)]
        [string]$LabPrefix,

        [Parameter()]
        [AllowNull()]
        [object]$WorkbookConfig
    )

    if (-not $WorkbookConfig -or -not $WorkbookConfig.PSObject.Properties['enabled'] -or -not [bool]$WorkbookConfig.enabled) {
        return $null
    }

    $name = if ($WorkbookConfig.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$WorkbookConfig.name)) { [string]$WorkbookConfig.name } else { 'Purview Signals' }
    $displayName = "$LabPrefix-$name"
    $workbookGuid = [guid]::NewGuid().ToString()

    $assetPath = Join-Path $PSScriptRoot 'assets' 'sentinel' 'arm' 'workbooks' 'purview.json'
    $template = Read-SentinelAsset -Path $assetPath
    $body = Expand-SentinelTemplate -Template $template -Tokens @{
        location            = $Scope.Location
        displayName         = $displayName
        workspaceResourceId = $Scope.WorkspaceResourceId
        labPrefix           = $LabPrefix
    }

    $url = "$($Scope.ArmBase)/subscriptions/$($Scope.SubscriptionId)/resourceGroups/$($Scope.ResourceGroup)/providers/Microsoft.Insights/workbooks/$workbookGuid`?api-version=2023-06-01"

    if (Test-SentinelWhatIf) {
        Write-LabLog -Message "[WhatIf] Would PUT workbook '$displayName'." -Level Info
        return @{ name = $displayName; id = "<planned-workbook:$displayName>"; workbookId = $workbookGuid }
    }

    try {
        $result = Invoke-SentinelAzRest -Method PUT -Url $url -Body $body
        Write-LabLog -Message "Deployed workbook '$displayName'." -Level Success
        return @{ name = $displayName; id = [string]$result.id; workbookId = $workbookGuid }
    }
    catch {
        Write-LabLog -Message "Workbook '$displayName' failed: $($_.Exception.Message)" -Level Warning
        return @{ name = $displayName; id = $null; workbookId = $workbookGuid; error = $_.Exception.Message }
    }
}

function Deploy-SentinelPlaybook {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter(Mandatory)]
        [string]$LabPrefix,

        [Parameter(Mandatory)]
        [string]$Template,

        [Parameter()]
        [string]$NameSuffix = 'IRM-AutoTriage'
    )

    $playbookName = "$LabPrefix-$NameSuffix"
    $assetPath = Join-Path $PSScriptRoot 'assets' 'sentinel' 'arm' 'playbooks' "$Template.json"
    if (-not (Test-Path $assetPath)) {
        Write-LabLog -Message "Playbook template '$Template' not found at $assetPath; skipping." -Level Warning
        return $null
    }

    if (Test-SentinelWhatIf) {
        Write-LabLog -Message "[WhatIf] Would deploy Logic App playbook '$playbookName'." -Level Info
        return @{
            name          = $playbookName
            id            = "<planned-playbook:$playbookName>"
            principalId   = $null
            deploymentName = $null
        }
    }

    $deploymentName = "pvsentinel-playbook-$playbookName".ToLower()
    if ($deploymentName.Length -gt 64) { $deploymentName = $deploymentName.Substring(0, 64) }

    $parameters = @{
        '$schema'       = 'https://schema.management.azure.com/schemas/2019-04-26/deploymentParameters.json#'
        contentVersion  = '1.0.0.0'
        parameters      = @{
            playbookName        = @{ value = $playbookName }
            location            = @{ value = $Scope.Location }
            workspaceResourceId = @{ value = $Scope.WorkspaceResourceId }
        }
    }

    $tempDir = [System.IO.Path]::GetTempPath()
    $templateFile = Join-Path $tempDir "pvsentinel-playbook-template-$([guid]::NewGuid().Guid).json"
    $paramsFile   = Join-Path $tempDir "pvsentinel-playbook-params-$([guid]::NewGuid().Guid).json"
    Copy-Item -Path $assetPath -Destination $templateFile -Force
    $parameters | ConvertTo-Json -Depth 20 | Set-Content -Path $paramsFile -Encoding utf8

    try {
        Write-LabLog -Message "Deploying playbook '$playbookName'..." -Level Info
        $raw = & az deployment group create `
            --subscription $Scope.SubscriptionId `
            --resource-group $Scope.ResourceGroup `
            --name $deploymentName `
            --template-file $templateFile `
            --parameters "@$paramsFile" `
            --only-show-errors 2>&1 | Out-String
        $result = $raw | ConvertFrom-Json -ErrorAction Stop
        $outputs = $result.properties.outputs
        $principalId = [string]$outputs.principalId.value
        $playbookResourceId = [string]$outputs.playbookResourceId.value
        Write-LabLog -Message "Deployed playbook '$playbookName' (principalId=$principalId)." -Level Success

        # Grant the playbook's managed identity "Microsoft Sentinel Responder" on the workspace
        # so the HTTP action inside the Logic App can post incident comments.
        try {
            $roleAssignId = [guid]::NewGuid().Guid
            $respondRoleId = '3e150937-b8fe-4cfb-8069-0eaf05ecd056' # Microsoft Sentinel Responder
            $roleUrl = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)/providers/Microsoft.Authorization/roleAssignments/$roleAssignId`?api-version=2022-04-01"
            $roleBody = @{
                properties = @{
                    roleDefinitionId = "/subscriptions/$($Scope.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$respondRoleId"
                    principalId      = $principalId
                    principalType    = 'ServicePrincipal'
                }
            }
            Invoke-SentinelAzRest -Method PUT -Url $roleUrl -Body ($roleBody | ConvertTo-Json -Depth 10) | Out-Null
            Write-LabLog -Message "Granted Microsoft Sentinel Responder to playbook identity on workspace." -Level Info
        }
        catch {
            Write-LabLog -Message "Playbook role assignment (Sentinel Responder) failed (may already exist): $($_.Exception.Message)" -Level Warning
        }

        # Grant the Sentinel first-party app "Logic App Contributor" on the playbook's RG
        # so the automation rule can invoke the Logic App. appId is the well-known Azure
        # Security Insights first-party app id.
        try {
            $sentinelAppId = '98785600-1bb7-4fb9-b9fa-19afe2c8a360'
            $spJson = & az ad sp show --id $sentinelAppId --only-show-errors 2>$null | Out-String
            $sp = $null
            if ($spJson) { $sp = $spJson | ConvertFrom-Json -ErrorAction SilentlyContinue }
            if ($sp -and $sp.id) {
                # Logic App Contributor at RG scope — lets Sentinel automation rules
                # read & invoke the playbook. This is the same role the portal grants
                # via "Manage playbook permissions".
                $laContribRoleId = '87a39d53-fc1b-424a-814c-f7e04687dc9e'
                $laAssignId = [guid]::NewGuid().Guid
                $rgScope = "/subscriptions/$($Scope.SubscriptionId)/resourceGroups/$($Scope.ResourceGroup)"
                $laUrl = "$($Scope.ArmBase)$rgScope/providers/Microsoft.Authorization/roleAssignments/$laAssignId`?api-version=2022-04-01"
                $laBody = @{
                    properties = @{
                        roleDefinitionId = "/subscriptions/$($Scope.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$laContribRoleId"
                        principalId      = $sp.id
                        principalType    = 'ServicePrincipal'
                    }
                }
                Invoke-SentinelAzRest -Method PUT -Url $laUrl -Body ($laBody | ConvertTo-Json -Depth 10) | Out-Null
                Write-LabLog -Message "Granted Sentinel first-party app Logic App Contributor on RG (enables automation-rule playbook invocation)." -Level Info
                # RBAC propagation is eventually consistent; pause before automation-rule PUT.
                Start-Sleep -Seconds 20
            }
            else {
                Write-LabLog -Message "Could not resolve Azure Security Insights service principal; automation rule may require manual playbook permissions in portal." -Level Warning
            }
        }
        catch {
            Write-LabLog -Message "Automation-rule role assignment failed (may already exist): $($_.Exception.Message)" -Level Warning
        }

        return @{
            name           = $playbookName
            id             = $playbookResourceId
            principalId    = $principalId
            deploymentName = $deploymentName
        }
    }
    catch {
        Write-LabLog -Message "Playbook '$playbookName' deployment failed: $($_.Exception.Message)" -Level Warning
        return @{ name = $playbookName; id = $null; error = $_.Exception.Message }
    }
    finally {
        if (Test-Path $templateFile) { Remove-Item $templateFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $paramsFile)   { Remove-Item $paramsFile   -Force -ErrorAction SilentlyContinue }
    }
}

function Deploy-SentinelAutomationRule {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter(Mandatory)]
        [string]$LabPrefix,

        [Parameter(Mandatory)]
        [string]$Template,

        [Parameter(Mandatory)]
        [string]$TriggerRuleResourceId,

        [Parameter(Mandatory)]
        [string]$PlaybookResourceId,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter()]
        [string]$NameSuffix = 'IRM-AutoTriage'
    )

    $displayName = "$LabPrefix-$NameSuffix"
    $assetPath = Join-Path $PSScriptRoot 'assets' 'sentinel' 'arm' 'automation-rules' "$Template.json"
    if (-not (Test-Path $assetPath)) {
        Write-LabLog -Message "Automation rule template '$Template' not found; skipping." -Level Warning
        return $null
    }

    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("purview-lab-deployer::automationRule::$displayName")) }
    finally { $md5.Dispose() }
    $ruleId = ([guid]::new($hash)).ToString()

    $template = Read-SentinelAsset -Path $assetPath
    $body = Expand-SentinelTemplate -Template $template -Tokens @{
        displayName        = $displayName
        ruleResourceId     = $TriggerRuleResourceId
        playbookResourceId = $PlaybookResourceId
        tenantId           = $TenantId
    }

    $url = "$($Scope.ArmBase)$($Scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/automationRules/$ruleId`?api-version=2023-11-01"

    if (Test-SentinelWhatIf) {
        Write-LabLog -Message "[WhatIf] Would PUT automation rule '$displayName'." -Level Info
        return @{ name = $displayName; id = "<planned-automation-rule:$displayName>"; ruleId = $ruleId }
    }

    try {
        $result = Invoke-SentinelAzRest -Method PUT -Url $url -Body $body
        Write-LabLog -Message "Deployed automation rule '$displayName'." -Level Success
        return @{ name = $displayName; id = [string]$result.id; ruleId = $ruleId }
    }
    catch {
        Write-LabLog -Message "Automation rule '$displayName' failed: $($_.Exception.Message)" -Level Warning
        return @{ name = $displayName; id = $null; ruleId = $ruleId; error = $_.Exception.Message }
    }
}


function Deploy-SentinelIntegration {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $s = $Config.workloads.sentinelIntegration
    $scope = Get-SentinelScope -Config $Config
    $labPrefix = [string]$Config.prefix

    $tenantId = $null
    if ($Config.PSObject.Properties['tenantId'] -and -not [string]::IsNullOrWhiteSpace([string]$Config.tenantId)) {
        $tenantId = [string]$Config.tenantId
    }
    elseif ($env:PURVIEW_TENANT_ID) {
        $tenantId = $env:PURVIEW_TENANT_ID
    }
    else {
        if (-not (Test-SentinelWhatIf)) {
            try {
                $acct = & az account show --only-show-errors 2>$null | ConvertFrom-Json
                if ($acct) { $tenantId = [string]$acct.tenantId }
            }
            catch { $tenantId = $null }
        }
    }
    if ([string]::IsNullOrWhiteSpace($tenantId)) { $tenantId = '<tenant-id>' }

    $manifest = @{
        subscriptionId        = $scope.SubscriptionId
        resourceGroup         = $scope.ResourceGroup
        location              = $scope.Location
        workspaceName         = $scope.WorkspaceName
        workspaceResourceId   = $scope.WorkspaceResourceId
        workspaceId           = $null
        createdResourceGroup  = $false
        onboardedBy           = $script:SentinelTag
        connectors            = @()
        rules                 = @()
        workbooks             = @()
        playbooks             = @()
        automationRules       = @()
    }

    # Resource group
    $rgResult = Deploy-SentinelResourceGroup -Scope $scope -LabPrefix $labPrefix
    $manifest.createdResourceGroup = [bool]$rgResult.created

    # Workspace
    $wsResult = Deploy-SentinelWorkspace -Scope $scope -LabPrefix $labPrefix
    $manifest.workspaceId = $wsResult.id

    # Sentinel onboarding
    Deploy-SentinelOnboarding -Scope $scope | Out-Null

    # Connectors
    if ($s.PSObject.Properties['connectors'] -and $s.connectors) {
        $manifest.connectors = Deploy-SentinelConnectors -Scope $scope -ConnectorsConfig $s.connectors -TenantId $tenantId
    }

    # Analytics rules
    if ($s.PSObject.Properties['analyticsRules']) {
        $manifest.rules = Deploy-SentinelAnalyticsRules -Scope $scope -LabPrefix $labPrefix -Rules $s.analyticsRules
    }

    # Workbook
    if ($s.PSObject.Properties['workbook']) {
        $wb = Deploy-SentinelWorkbook -Scope $scope -LabPrefix $labPrefix -WorkbookConfig $s.workbook
        if ($wb) { $manifest.workbooks = @($wb) }
    }

    # Playbook + automation rule (IRM auto-triage)
    if ($s.PSObject.Properties['playbooks'] -and $s.playbooks -and
        $s.playbooks.PSObject.Properties['irmAutoTriage'] -and
        [bool]$s.playbooks.irmAutoTriage.enabled) {
        $playbook = Deploy-SentinelPlaybook -Scope $scope -LabPrefix $labPrefix -Template 'irm-auto-triage' -NameSuffix 'IRM-AutoTriage'
        if ($playbook) { $manifest.playbooks = @($playbook) }

        if ($playbook -and $playbook.id -and -not $playbook.error) {
            $irmRule = @($manifest.rules) | Where-Object { $_ -and $_.template -eq 'insider-risk-high-severity' -and $_.id } | Select-Object -First 1
            if ($irmRule) {
                $autoRule = Deploy-SentinelAutomationRule `
                    -Scope $scope `
                    -LabPrefix $labPrefix `
                    -Template 'irm-auto-triage' `
                    -TriggerRuleResourceId ([string]$irmRule.id) `
                    -PlaybookResourceId   ([string]$playbook.id) `
                    -TenantId $tenantId `
                    -NameSuffix 'IRM-AutoTriage'
                if ($autoRule) { $manifest.automationRules = @($autoRule) }
            }
            else {
                Write-LabLog -Message "IRM analytics rule not available (did it deploy?); skipping automation-rule wiring." -Level Warning
            }
        }
    }

    if (-not (Test-SentinelWhatIf)) {
        Write-LabLog -Message "Sentinel lab deployed. Workspace: $($scope.WorkspaceName) | RG: $($scope.ResourceGroup) | Connectors: $($manifest.connectors.Count) | Rules: $($manifest.rules.Count)" -Level Success
        if ($s.connectors -and $s.connectors.insiderRiskManagement -and [bool]$s.connectors.insiderRiskManagement.enabled) {
            Write-LabLog -Message 'Reminder: enable Insider Risk SIEM export in the Purview portal (Insider risk > Settings > Export alerts). This tenant-side toggle is not ARM-configurable.' -Level Warning
        }
    }

    return $manifest
}

function Test-SentinelRgDeletionAuthorized {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Scope,

        [Parameter()]
        [AllowNull()]
        [object]$Manifest,

        [Parameter()]
        [switch]$ForceDeleteResourceGroup
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    if (-not $ForceDeleteResourceGroup) {
        $reasons.Add('ForceDeleteResourceGroup switch was not provided.')
    }
    if (-not $Manifest) {
        $reasons.Add('No manifest provided; refusing destructive Azure operations.')
    }
    else {
        if (-not $Manifest.PSObject.Properties['createdResourceGroup'] -or -not [bool]$Manifest.createdResourceGroup) {
            $reasons.Add('Manifest does not record createdResourceGroup=true; will not delete a pre-existing RG.')
        }
        if ($Manifest.PSObject.Properties['resourceGroup'] -and [string]$Manifest.resourceGroup -ne $Scope.ResourceGroup) {
            $reasons.Add("Manifest resource group '$($Manifest.resourceGroup)' does not match config '$($Scope.ResourceGroup)'.")
        }
        if ($Manifest.PSObject.Properties['subscriptionId'] -and [string]$Manifest.subscriptionId -ne $Scope.SubscriptionId) {
            $reasons.Add("Manifest subscriptionId does not match config subscriptionId.")
        }
    }

    # Tag check — only meaningful when we have live auth
    if (-not (Test-SentinelWhatIf) -and $reasons.Count -eq 0) {
        $url = "$($Scope.ArmBase)/subscriptions/$($Scope.SubscriptionId)/resourcegroups/$($Scope.ResourceGroup)?api-version=2021-04-01"
        try {
            $rg = Invoke-SentinelAzRest -Method GET -Url $url -AllowMissing
            if (-not $rg) {
                $reasons.Add("Resource group '$($Scope.ResourceGroup)' does not exist; nothing to delete.")
            }
            elseif (-not $rg.tags -or -not $rg.tags.createdBy -or [string]$rg.tags.createdBy -ne $script:SentinelTag) {
                $reasons.Add("RG tag 'createdBy' is not '$($script:SentinelTag)'; refusing to delete.")
            }
        }
        catch {
            $reasons.Add("Tag verification failed: $($_.Exception.Message)")
        }
    }

    return @{
        authorized = ($reasons.Count -eq 0)
        reasons    = $reasons.ToArray()
    }
}

function Remove-SentinelIntegration {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [AllowNull()]
        [object]$Manifest,

        [Parameter()]
        [switch]$ForceDeleteResourceGroup
    )

    $scope = Get-SentinelScope -Config $Config

    if (-not $Manifest) {
        Write-LabLog -Message 'No Sentinel manifest provided. Refusing destructive Azure operations. Child-resource teardown requires a manifest (precise resource IDs).' -Level Warning
        Write-LabLog -Message 'Remediation: re-run Remove-Lab.ps1 with -ManifestPath pointing at the deployment manifest.' -Level Info
        return
    }

    # 1. Workbooks
    foreach ($wb in @($Manifest.workbooks)) {
        if (-not $wb -or -not $wb.workbookId) { continue }
        $url = "$($scope.ArmBase)/subscriptions/$($scope.SubscriptionId)/resourceGroups/$($scope.ResourceGroup)/providers/Microsoft.Insights/workbooks/$($wb.workbookId)?api-version=2023-06-01"
        if ($PSCmdlet.ShouldProcess($wb.name, 'Remove Sentinel workbook')) {
            if (Test-SentinelWhatIf) {
                Write-LabLog -Message "[WhatIf] Would DELETE workbook '$($wb.name)'." -Level Info
            }
            else {
                Invoke-SentinelAzRest -Method DELETE -Url $url -AllowMissing | Out-Null
                Write-LabLog -Message "Removed workbook '$($wb.name)'." -Level Info
            }
        }
    }

    # 1b. Automation rules (before playbooks — they reference the playbook)
    foreach ($ar in @($Manifest.automationRules)) {
        if (-not $ar -or -not $ar.ruleId) { continue }
        $url = "$($scope.ArmBase)$($scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/automationRules/$($ar.ruleId)?api-version=2023-11-01"
        if ($PSCmdlet.ShouldProcess($ar.name, 'Remove Sentinel automation rule')) {
            if (Test-SentinelWhatIf) {
                Write-LabLog -Message "[WhatIf] Would DELETE automation rule '$($ar.name)'." -Level Info
            }
            else {
                Invoke-SentinelAzRest -Method DELETE -Url $url -AllowMissing | Out-Null
                Write-LabLog -Message "Removed automation rule '$($ar.name)'." -Level Info
            }
        }
    }

    # 1c. Playbooks (Logic Apps) + their API connections
    foreach ($pb in @($Manifest.playbooks)) {
        if (-not $pb -or -not $pb.name) { continue }
        $url = "$($scope.ArmBase)/subscriptions/$($scope.SubscriptionId)/resourceGroups/$($scope.ResourceGroup)/providers/Microsoft.Logic/workflows/$($pb.name)?api-version=2019-05-01"
        if ($PSCmdlet.ShouldProcess($pb.name, 'Remove Sentinel playbook')) {
            if (Test-SentinelWhatIf) {
                Write-LabLog -Message "[WhatIf] Would DELETE playbook '$($pb.name)'." -Level Info
            }
            else {
                Invoke-SentinelAzRest -Method DELETE -Url $url -AllowMissing | Out-Null
                Write-LabLog -Message "Removed playbook '$($pb.name)'." -Level Info
                # Best-effort cleanup of the associated azuresentinel API connection.
                $connName = "azuresentinel-$($pb.name)"
                $connUrl = "$($scope.ArmBase)/subscriptions/$($scope.SubscriptionId)/resourceGroups/$($scope.ResourceGroup)/providers/Microsoft.Web/connections/$connName`?api-version=2016-06-01"
                Invoke-SentinelAzRest -Method DELETE -Url $connUrl -AllowMissing | Out-Null
            }
        }
    }

    # 2. Analytics rules
    foreach ($rule in @($Manifest.rules)) {
        if (-not $rule -or -not $rule.ruleId) { continue }
        $url = "$($scope.ArmBase)$($scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/alertRules/$($rule.ruleId)?api-version=2023-11-01"
        if ($PSCmdlet.ShouldProcess($rule.name, 'Remove analytics rule')) {
            if (Test-SentinelWhatIf) {
                Write-LabLog -Message "[WhatIf] Would DELETE analytics rule '$($rule.name)'." -Level Info
            }
            else {
                Invoke-SentinelAzRest -Method DELETE -Url $url -AllowMissing | Out-Null
                Write-LabLog -Message "Removed analytics rule '$($rule.name)'." -Level Info
            }
        }
    }

    # 3. Data connectors
    foreach ($c in @($Manifest.connectors)) {
        if (-not $c -or -not $c.name) { continue }
        $url = "$($scope.ArmBase)$($scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/dataConnectors/$($c.name)?api-version=2023-11-01"
        if ($PSCmdlet.ShouldProcess($c.name, 'Remove data connector')) {
            if (Test-SentinelWhatIf) {
                Write-LabLog -Message "[WhatIf] Would DELETE data connector '$($c.name)'." -Level Info
            }
            else {
                Invoke-SentinelAzRest -Method DELETE -Url $url -AllowMissing | Out-Null
                Write-LabLog -Message "Removed data connector '$($c.name)'." -Level Info
            }
        }
    }

    # 4. Sentinel onboarding
    $onboardingUrl = "$($scope.ArmBase)$($scope.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2023-11-01"
    if ($PSCmdlet.ShouldProcess("$($scope.WorkspaceName) onboarding", 'Remove Sentinel onboarding')) {
        if (Test-SentinelWhatIf) {
            Write-LabLog -Message "[WhatIf] Would DELETE Sentinel onboarding on workspace '$($scope.WorkspaceName)'." -Level Info
        }
        else {
            Invoke-SentinelAzRest -Method DELETE -Url $onboardingUrl -AllowMissing | Out-Null
            Write-LabLog -Message "Removed Sentinel onboarding on workspace '$($scope.WorkspaceName)'." -Level Info
        }
    }

    # 5. Workspace
    $wsUrl = "$($scope.ArmBase)$($scope.WorkspaceResourceId)?api-version=2022-10-01&force=true"
    if ($PSCmdlet.ShouldProcess($scope.WorkspaceName, 'Remove Log Analytics workspace')) {
        if (Test-SentinelWhatIf) {
            Write-LabLog -Message "[WhatIf] Would DELETE workspace '$($scope.WorkspaceName)'." -Level Info
        }
        else {
            Invoke-SentinelAzRest -Method DELETE -Url $wsUrl -AllowMissing | Out-Null
            Write-LabLog -Message "Removed workspace '$($scope.WorkspaceName)'." -Level Info
        }
    }

    # 6. Resource group (gated)
    $gate = Test-SentinelRgDeletionAuthorized -Scope $scope -Manifest $Manifest -ForceDeleteResourceGroup:$ForceDeleteResourceGroup
    if (-not $gate.authorized) {
        Write-LabLog -Message "Skipping resource group deletion for '$($scope.ResourceGroup)'. Reasons: $($gate.reasons -join '; ')" -Level Warning
        return
    }

    $rgUrl = "$($scope.ArmBase)/subscriptions/$($scope.SubscriptionId)/resourcegroups/$($scope.ResourceGroup)?api-version=2021-04-01"
    if ($PSCmdlet.ShouldProcess($scope.ResourceGroup, 'Delete resource group (destructive)')) {
        if (Test-SentinelWhatIf) {
            Write-LabLog -Message "[WhatIf] Would DELETE resource group '$($scope.ResourceGroup)'." -Level Warning
        }
        else {
            Invoke-SentinelAzRest -Method DELETE -Url $rgUrl -AllowMissing | Out-Null
            Write-LabLog -Message "Deleted resource group '$($scope.ResourceGroup)'." -Level Success
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-SentinelIntegration'
    'Remove-SentinelIntegration'
    'Get-SentinelScope'
    'Expand-SentinelTemplate'
    'Test-SentinelRgDeletionAuthorized'
    'Deploy-SentinelResourceGroup'
    'Deploy-SentinelWorkspace'
    'Deploy-SentinelOnboarding'
    'Deploy-SentinelConnectors'
    'Deploy-SentinelAnalyticsRules'
    'Deploy-SentinelWorkbook'
    'Deploy-SentinelPlaybook'
    'Deploy-SentinelAutomationRule'
    'Install-SentinelContentHubSolution'
    'Invoke-SentinelAzRest'
)
