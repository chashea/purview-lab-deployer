#Requires -Version 7.0

<#
.SYNOPSIS
    Microsoft Foundry workload module for purview-lab-deployer.
.DESCRIPTION
    Deploys a Microsoft Foundry account (Microsoft.CognitiveServices/accounts kind=AIServices),
    a gpt-4o model deployment, a Foundry project, a Purview governance toggle, and AI agents.
    Uses the 2025 Foundry resource model — no Hub, Storage, or Key Vault required.
    Requires the Az.Accounts PowerShell module for ARM authentication.
#>

$script:ArmApiVersion   = '2025-06-01'
$script:AgentApiVersion = '2025-05-01'
$script:ArmBase         = 'https://management.azure.com'
$script:GptModelVersion = '2024-11-20'   # Current GA version of gpt-4o; update if deploying to a region with a newer default

# ─── Private helpers ──────────────────────────────────────────────────────────

function Get-FoundryArmToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $tok = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com' -ErrorAction Stop).Token
    # Az.Accounts 3.x+ returns a SecureString; convert to plain text for HTTP headers
    if ($tok -is [System.Security.SecureString]) { return $tok | ConvertFrom-SecureString -AsPlainText }
    return $tok
}

function Get-FoundryDataToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $tok = (Get-AzAccessToken -ResourceUrl 'https://cognitiveservices.azure.com' -ErrorAction Stop).Token
    if ($tok -is [System.Security.SecureString]) { return $tok | ConvertFrom-SecureString -AsPlainText }
    return $tok
}

function Invoke-ArmGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $headers = @{ 'Authorization' = "Bearer $Token" }
    $webResponse = Invoke-WebRequest -Uri $Uri -Method Get -Headers $headers `
        -SkipHttpErrorCheck -ErrorAction Stop

    $statusCode = [int]$webResponse.StatusCode
    if ($statusCode -eq 404) { return $null }
    if ($statusCode -ge 400) {
        throw "ARM GET failed (HTTP $statusCode): $($webResponse.Content)"
    }

    return ($webResponse.Content | ConvertFrom-Json)
}

function Invoke-ArmPut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Body,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter()]
        [switch]$Async
    )

    $headers = @{
        'Authorization' = "Bearer $Token"
        'Content-Type'  = 'application/json'
    }

    $webResponse = Invoke-WebRequest -Uri $Uri -Method Put -Headers $headers -Body $Body `
        -SkipHttpErrorCheck -ErrorAction Stop
    $statusCode = [int]$webResponse.StatusCode

    if ($statusCode -ge 400) {
        throw "ARM PUT failed (HTTP $statusCode): $($webResponse.Content)"
    }

    $parsed = if ($webResponse.Content) {
        try { $webResponse.Content | ConvertFrom-Json } catch { $null }
    }
    else { $null }

    if ($Async -and $statusCode -in @(201, 202)) {
        $asyncUrl = $null
        if ($webResponse.Headers['Azure-AsyncOperation']) {
            $asyncUrl = [string]($webResponse.Headers['Azure-AsyncOperation'] | Select-Object -First 1)
        }
        elseif ($webResponse.Headers['Location']) {
            $asyncUrl = [string]($webResponse.Headers['Location'] | Select-Object -First 1)
        }

        if ($asyncUrl) {
            Wait-ArmAsyncOperation -OperationUrl $asyncUrl -Token $Token
        }
    }

    return $parsed
}

function Invoke-ArmDelete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter()]
        [switch]$Async
    )

    $headers = @{ 'Authorization' = "Bearer $Token" }
    $webResponse = Invoke-WebRequest -Uri $Uri -Method Delete -Headers $headers `
        -SkipHttpErrorCheck -ErrorAction Stop
    $statusCode = [int]$webResponse.StatusCode

    if ($statusCode -eq 404) { return }  # Already gone
    if ($statusCode -ge 400) {
        throw "ARM DELETE failed (HTTP $statusCode): $($webResponse.Content)"
    }

    if ($Async -and $statusCode -eq 202) {
        $asyncUrl = $null
        if ($webResponse.Headers['Azure-AsyncOperation']) {
            $asyncUrl = [string]($webResponse.Headers['Azure-AsyncOperation'] | Select-Object -First 1)
        }
        elseif ($webResponse.Headers['Location']) {
            $asyncUrl = [string]($webResponse.Headers['Location'] | Select-Object -First 1)
        }

        if ($asyncUrl) {
            Wait-ArmAsyncOperation -OperationUrl $asyncUrl -Token $Token
        }
    }
}

function Wait-ArmAsyncOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationUrl,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $headers    = @{ 'Authorization' = "Bearer $Token" }
    $maxAttempts = 40   # 40 × 15s = 10 min

    for ($i = 1; $i -le $maxAttempts; $i++) {
        Start-Sleep -Seconds 15
        $opResponse = Invoke-WebRequest -Uri $OperationUrl -Method Get -Headers $headers `
            -SkipHttpErrorCheck -ErrorAction Stop
        $opBody = try { $opResponse.Content | ConvertFrom-Json } catch { $null }

        $httpStatus = [int]$opResponse.StatusCode

        # For Location-header style polling: 200/204 with no status body = operation complete
        if ($httpStatus -in @(200, 204) -and (-not $opBody -or (-not $opBody.PSObject.Properties['status'] -and -not $opBody.PSObject.Properties['provisioningState']))) {
            Write-LabLog -Message "ARM async polling... status: Succeeded (HTTP $httpStatus, attempt $i/$maxAttempts)" -Level Info
            return
        }

        $status = if ($opBody) {
            if ($opBody.PSObject.Properties['status']) {
                [string]$opBody.status
            }
            elseif ($opBody.PSObject.Properties['provisioningState']) {
                [string]$opBody.provisioningState
            }
            else { 'Unknown' }
        }
        else { 'Unknown' }

        Write-LabLog -Message "ARM async polling... status: $status (attempt $i/$maxAttempts)" -Level Info

        if ($status -eq 'Succeeded') { return }
        if ($status -in @('Failed', 'Canceled')) {
            $errorMsg = if ($opBody -and $opBody.PSObject.Properties['error']) {
                $opBody.error | ConvertTo-Json -Compress
            }
            else { $opResponse.Content }
            throw "ARM async operation $status`: $errorMsg"
        }
    }

    throw "ARM async operation did not complete within $($maxAttempts * 15) seconds."
}


# ─── Deploy-Foundry ───────────────────────────────────────────────────────────

function Deploy-Foundry {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $fw              = $Config.workloads.foundry
    $subscriptionId  = [string]$fw.subscriptionId
    $resourceGroup   = [string]$fw.resourceGroup
    $location        = [string]$fw.location
    $accountName     = [string]$fw.accountName
    $projectName     = [string]$fw.projectName
    $modelDeployName = [string]$fw.modelDeploymentName

    # Validate required config fields
    if ([string]::IsNullOrWhiteSpace($subscriptionId) -or $subscriptionId -eq 'YOUR_SUBSCRIPTION_ID') {
        throw 'foundry.subscriptionId must be set to a real Azure subscription ID before deploying.'
    }
    foreach ($field in @('resourceGroup', 'location', 'accountName', 'projectName', 'modelDeploymentName')) {
        if ([string]::IsNullOrWhiteSpace([string]$fw.$field)) {
            throw "foundry.$field is required but not set in the config."
        }
    }

    $manifest = [PSCustomObject]@{
        subscriptionId            = $subscriptionId
        resourceGroup             = $resourceGroup
        location                  = $location
        accountId                 = $null
        projectId                 = $null
        projectEndpoint           = $null
        modelDeploymentName       = $modelDeployName
        purviewIntegrationEnabled = $false
        agents                    = @()
    }

    if (-not $PSCmdlet.ShouldProcess("Foundry lab '$($Config.prefix)'", 'Deploy Foundry account, project, and agents')) {
        return $manifest
    }

    # Re-assert Az context with the target subscription before acquiring tokens.
    # The Purview workloads run for 10-30 min before Foundry; re-setting context
    # ensures Get-AzAccessToken issues a fresh token for the correct subscription.
    Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null

    $armToken  = Get-FoundryArmToken
    $dataToken = Get-FoundryDataToken

    $subPath     = "$($script:ArmBase)/subscriptions/$subscriptionId"
    $rgPath      = "$subPath/resourceGroups/$resourceGroup"
    $accountPath = "$rgPath/providers/Microsoft.CognitiveServices/accounts/$accountName"
    $modelPath   = "$accountPath/deployments/$modelDeployName"
    $projectPath = "$accountPath/projects/$projectName"

    # ── 1. Resource Group ──────────────────────────────────────────────────────
    Write-LabLog -Message "Ensuring resource group: $resourceGroup" -Level Info
    $rgUri = "$rgPath`?api-version=2021-04-01"
    $existingRg = Invoke-ArmGet -Uri $rgUri -Token $armToken
    if (-not $existingRg) {
        $rgBody = @{ location = $location } | ConvertTo-Json -Compress
        Invoke-ArmPut -Uri $rgUri -Body $rgBody -Token $armToken | Out-Null
        Write-LabLog -Message "Created resource group: $resourceGroup" -Level Success
    }
    else {
        Write-LabLog -Message "Resource group already exists: $resourceGroup" -Level Info
    }

    # ── 2. Foundry Account (CognitiveServices AIServices) ──────────────────────
    Write-LabLog -Message "Ensuring Foundry account: $accountName" -Level Info
    $accountUri      = "$accountPath`?api-version=$($script:ArmApiVersion)"
    $existingAccount = Invoke-ArmGet -Uri $accountUri -Token $armToken

    if ($existingAccount) {
        Write-LabLog -Message "Foundry account already exists: $accountName" -Level Info
        $manifest.accountId = [string]$existingAccount.id
    }
    else {
        $accountBody = @{
            kind       = 'AIServices'
            location   = $location
            sku        = @{ name = 'S0' }
            properties = @{
                allowProjectManagement = $true
                publicNetworkAccess    = 'Enabled'
                customSubDomainName    = $accountName   # Required for Foundry project creation
            }
        } | ConvertTo-Json -Depth 5 -Compress

        $createdAccount = Invoke-ArmPut -Uri $accountUri -Body $accountBody -Token $armToken -Async
        $manifest.accountId = if ($createdAccount -and $createdAccount.PSObject.Properties['id']) {
            [string]$createdAccount.id
        }
        else { $accountPath }
        Write-LabLog -Message "Created Foundry account: $accountName" -Level Success
    }

    # ── 3. Model Deployment (gpt-4o GlobalStandard) ───────────────────────────
    Write-LabLog -Message "Ensuring model deployment: $modelDeployName" -Level Info
    $modelUri      = "$modelPath`?api-version=$($script:ArmApiVersion)"
    $existingModel = Invoke-ArmGet -Uri $modelUri -Token $armToken

    if ($existingModel) {
        Write-LabLog -Message "Model deployment already exists: $modelDeployName" -Level Info
    }
    else {
        $modelBody = @{
            sku        = @{ name = 'GlobalStandard'; capacity = 10 }
            properties = @{
                model = @{
                    format  = 'OpenAI'
                    name    = 'gpt-4o'
                    version = $script:GptModelVersion
                }
            }
        } | ConvertTo-Json -Depth 5 -Compress

        Invoke-ArmPut -Uri $modelUri -Body $modelBody -Token $armToken -Async | Out-Null
        Write-LabLog -Message "Created model deployment: $modelDeployName (gpt-4o $($script:GptModelVersion))" -Level Success
    }

    # ── 4. Foundry Project ────────────────────────────────────────────────────
    Write-LabLog -Message "Ensuring Foundry project: $projectName" -Level Info
    $projectUri      = "$projectPath`?api-version=$($script:ArmApiVersion)"
    $existingProject = Invoke-ArmGet -Uri $projectUri -Token $armToken

    if ($existingProject) {
        Write-LabLog -Message "Foundry project already exists: $projectName" -Level Info
        $manifest.projectId = [string]$existingProject.id
    }
    else {
        $projectBody = @{
            location   = $location
            kind       = 'Project'
            properties = @{
                description = 'Purview AI governance demo — deployed by purview-lab-deployer'
            }
        } | ConvertTo-Json -Depth 5 -Compress

        $createdProject = Invoke-ArmPut -Uri $projectUri -Body $projectBody -Token $armToken -Async
        $manifest.projectId = if ($createdProject -and $createdProject.PSObject.Properties['id']) {
            [string]$createdProject.id
        }
        else { $projectPath }
        Write-LabLog -Message "Created Foundry project: $projectName" -Level Success
    }

    $projectEndpoint          = "https://$accountName.services.ai.azure.com/api/projects/$projectName"
    $manifest.projectEndpoint = $projectEndpoint

    # ── 5. Enable Purview governance integration (best-effort REST) ────────────
    try {
        $govUri  = "$projectEndpoint/governance/settings?api-version=$($script:AgentApiVersion)"
        $govBody = @{ purviewIntegrationEnabled = $true } | ConvertTo-Json -Compress
        $govHeaders = @{
            'Authorization' = "Bearer $dataToken"
            'Content-Type'  = 'application/json'
        }
        $govResponse = Invoke-WebRequest -Uri $govUri -Method Put -Headers $govHeaders -Body $govBody `
            -SkipHttpErrorCheck -ErrorAction Stop

        if ([int]$govResponse.StatusCode -lt 400) {
            $manifest.purviewIntegrationEnabled = $true
            Write-LabLog -Message 'Purview governance integration enabled on Foundry project.' -Level Success
        }
        else {
            Write-LabLog -Message "Purview governance toggle returned HTTP $($govResponse.StatusCode). Enable integration manually: Foundry portal > Governance settings." -Level Warning
        }
    }
    catch {
        Write-LabLog -Message "Purview governance toggle not available via API. Enable manually: Foundry portal > Governance settings. ($($_.Exception.Message))" -Level Warning
    }

    # ── 6. Create agents ───────────────────────────────────────────────────────
    $createdAgents = [System.Collections.Generic.List[PSCustomObject]]::new()
    $agentHeaders  = @{
        'Authorization' = "Bearer $dataToken"
        'Content-Type'  = 'application/json'
    }
    $agentsUri = "$projectEndpoint/assistants?api-version=$($script:AgentApiVersion)"

    foreach ($agentConfig in $Config.workloads.foundry.agents) {
        $agentName = "$($Config.prefix)-$($agentConfig.name)"
        Write-LabLog -Message "Creating agent: $agentName" -Level Info

        $agentPayload = [ordered]@{
            name         = $agentName
            model        = [string]$agentConfig.model
            instructions = [string]$agentConfig.instructions
        }
        if ($agentConfig.PSObject.Properties['description'] -and
            -not [string]::IsNullOrWhiteSpace([string]$agentConfig.description)) {
            $agentPayload['description'] = [string]$agentConfig.description
        }

        try {
            $agentResponse = Invoke-WebRequest -Uri $agentsUri -Method Post -Headers $agentHeaders `
                -Body ($agentPayload | ConvertTo-Json -Compress) -SkipHttpErrorCheck -ErrorAction Stop

            if ([int]$agentResponse.StatusCode -lt 400) {
                $agentResult = $agentResponse.Content | ConvertFrom-Json
                $createdAgents.Add([PSCustomObject]@{
                    id    = [string]$agentResult.id
                    name  = $agentName
                    model = [string]$agentConfig.model
                })
                Write-LabLog -Message "Created agent: $agentName (id: $($agentResult.id))" -Level Success
            }
            else {
                Write-LabLog -Message "Agent '$agentName' creation failed (HTTP $($agentResponse.StatusCode)): $($agentResponse.Content)" -Level Warning
            }
        }
        catch {
            Write-LabLog -Message "Error creating agent '$agentName'`: $($_.Exception.Message)" -Level Warning
        }
    }

    $manifest.agents = $createdAgents.ToArray()
    return $manifest
}


# ─── Remove-Foundry ───────────────────────────────────────────────────────────

function Remove-Foundry {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    $fw = $Config.workloads.foundry

    $subscriptionId = if ($Manifest -and $Manifest.PSObject.Properties['subscriptionId']) {
        [string]$Manifest.subscriptionId
    }
    else { [string]$fw.subscriptionId }

    $resourceGroup = if ($Manifest -and $Manifest.PSObject.Properties['resourceGroup']) {
        [string]$Manifest.resourceGroup
    }
    else { [string]$fw.resourceGroup }

    $accountName     = [string]$fw.accountName
    $projectName     = [string]$fw.projectName
    $modelDeployName = [string]$fw.modelDeploymentName

    $projectEndpoint = if ($Manifest -and $Manifest.PSObject.Properties['projectEndpoint'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Manifest.projectEndpoint)) {
        [string]$Manifest.projectEndpoint
    }
    else {
        "https://$accountName.services.ai.azure.com/api/projects/$projectName"
    }

    if ([string]::IsNullOrWhiteSpace($subscriptionId) -or $subscriptionId -eq 'YOUR_SUBSCRIPTION_ID') {
        Write-LabLog -Message 'foundry.subscriptionId not configured — skipping Foundry teardown.' -Level Warning
        return
    }

    if (-not $PSCmdlet.ShouldProcess("Foundry lab '$($Config.prefix)'", 'Remove Foundry agents, project, and account')) {
        return
    }

    Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null

    $armToken  = Get-FoundryArmToken
    $dataToken = Get-FoundryDataToken

    $rgPath      = "$($script:ArmBase)/subscriptions/$subscriptionId/resourceGroups/$resourceGroup"
    $accountPath = "$rgPath/providers/Microsoft.CognitiveServices/accounts/$accountName"

    # ── 1. Delete agents ───────────────────────────────────────────────────────
    $agentsToDelete = @()
    if ($Manifest -and $Manifest.PSObject.Properties['agents'] -and $Manifest.agents) {
        $agentsToDelete = @($Manifest.agents)
    }
    else {
        Write-LabLog -Message 'No agent manifest available — delete agents manually in the Foundry portal.' -Level Warning
    }

    $agentHeaders = @{
        'Authorization' = "Bearer $dataToken"
        'Content-Type'  = 'application/json'
    }

    foreach ($agent in $agentsToDelete) {
        $agentId   = [string]$agent.id
        $agentName = [string]$agent.name
        if ([string]::IsNullOrWhiteSpace($agentId)) { continue }

        try {
            $deleteUri   = "$projectEndpoint/assistants/$($agentId)?api-version=$($script:AgentApiVersion)"
            $delResponse = Invoke-WebRequest -Uri $deleteUri -Method Delete -Headers $agentHeaders `
                -SkipHttpErrorCheck -ErrorAction Stop

            if ([int]$delResponse.StatusCode -lt 400) {
                Write-LabLog -Message "Deleted agent: $agentName ($agentId)" -Level Success
            }
            else {
                Write-LabLog -Message "Agent delete HTTP $($delResponse.StatusCode) for '$agentName' — may already be removed." -Level Warning
            }
        }
        catch {
            Write-LabLog -Message "Error deleting agent '$agentName' ($agentId)`: $($_.Exception.Message)" -Level Warning
        }
    }

    # ── 2. Delete Foundry Project ──────────────────────────────────────────────
    Write-LabLog -Message "Removing Foundry project: $projectName" -Level Info
    try {
        Invoke-ArmDelete -Uri "$accountPath/projects/$projectName`?api-version=$($script:ArmApiVersion)" `
            -Token $armToken -Async
        Write-LabLog -Message "Removed Foundry project: $projectName" -Level Success
    }
    catch {
        Write-LabLog -Message "Error removing Foundry project '$projectName'`: $($_.Exception.Message)" -Level Warning
    }

    # ── 3. Delete Model Deployment ─────────────────────────────────────────────
    Write-LabLog -Message "Removing model deployment: $modelDeployName" -Level Info
    try {
        Invoke-ArmDelete -Uri "$accountPath/deployments/$modelDeployName`?api-version=$($script:ArmApiVersion)" `
            -Token $armToken -Async
        Write-LabLog -Message "Removed model deployment: $modelDeployName" -Level Success
    }
    catch {
        Write-LabLog -Message "Error removing model deployment '$modelDeployName'`: $($_.Exception.Message)" -Level Warning
    }

    # ── 4. Delete Foundry Account ──────────────────────────────────────────────
    Write-LabLog -Message "Removing Foundry account: $accountName" -Level Info
    try {
        Invoke-ArmDelete -Uri "$accountPath`?api-version=$($script:ArmApiVersion)" `
            -Token $armToken -Async
        Write-LabLog -Message "Removed Foundry account: $accountName" -Level Success
    }
    catch {
        Write-LabLog -Message "Error removing Foundry account '$accountName'`: $($_.Exception.Message)" -Level Warning
    }

    # ── 5. Delete Resource Group (cascades remaining resources) ───────────────
    Write-LabLog -Message "Removing resource group: $resourceGroup" -Level Info
    try {
        Invoke-ArmDelete -Uri "$rgPath`?api-version=2021-04-01" -Token $armToken -Async
        Write-LabLog -Message "Removed resource group: $resourceGroup" -Level Success
    }
    catch {
        Write-LabLog -Message "Error removing resource group '$resourceGroup'`: $($_.Exception.Message)" -Level Warning
    }
}

Export-ModuleMember -Function @(
    'Deploy-Foundry'
    'Remove-Foundry'
)
