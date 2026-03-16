#Requires -Version 7.0

<#
.SYNOPSIS
    Main deployment orchestrator for purview-lab-deployer.

.DESCRIPTION
    Deploys Microsoft Purview lab workloads in dependency order based on a
    JSON configuration file. Produces a manifest of all created resources
    for later teardown.

.PARAMETER ConfigPath
    Path to the lab configuration JSON file.

.PARAMETER SkipAuth
    Skip connecting to Exchange Online and Microsoft Graph (for testing).

.EXAMPLE
    ./Deploy-Lab.ps1 -ConfigPath configs/full-demo.json

.EXAMPLE
    ./Deploy-Lab.ps1 -ConfigPath configs/full-demo.json -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [Parameter()]
    [switch]$SkipAuth
)

$ErrorActionPreference = 'Stop'

# Import all modules
foreach ($mod in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'modules') -Filter '*.psm1')) {
    Import-Module $mod.FullName -Force
}

try {
    # Initialize logging
    Initialize-LabLogging -Prefix 'PurviewLab'
    Write-LabLog -Message 'Deploy-Lab started.' -Level Info

    # Load configuration
    Write-LabStep -StepName 'Config' -Description 'Loading lab configuration'
    $Config = Import-LabConfig -ConfigPath $ConfigPath
    Write-LabLog -Message "Lab: $($Config.labName) | Prefix: $($Config.prefix) | Domain: $($Config.domain)" -Level Info

    # Test prerequisites
    Write-LabStep -StepName 'Prerequisites' -Description 'Validating prerequisites'
    if (-not (Test-LabPrerequisites)) {
        Write-LabLog -Message 'Prerequisites check failed. Exiting.' -Level Error
        exit 1
    }
    Write-LabLog -Message 'All prerequisites satisfied.' -Level Success

    # Connect to services
    if (-not $SkipAuth) {
        Write-LabStep -StepName 'Auth' -Description 'Connecting to cloud services'
        Connect-LabServices -TenantId 'f1b92d41-6d54-4102-9dd9-4208451314df'
        Write-LabLog -Message 'Connected to Exchange Online and Microsoft Graph.' -Level Success
    }
    else {
        Write-LabLog -Message 'Skipping authentication (-SkipAuth).' -Level Warning
    }

    # Initialize manifest
    $manifest = @{}

    # Deploy workloads in dependency order
    # 1. Test Users
    if ($Config.workloads.testUsers.enabled) {
        Write-LabStep -StepName 'TestUsers' -Description 'Deploying test users'
        $result = Deploy-TestUsers -Config $Config -WhatIf:$WhatIfPreference
        if ($result) { $manifest['testUsers'] = $result }
        Write-LabLog -Message 'Test users deployment complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'testUsers workload is disabled, skipping.' -Level Info
    }

    # 2. Sensitivity Labels
    if ($Config.workloads.sensitivityLabels.enabled) {
        Write-LabStep -StepName 'SensitivityLabels' -Description 'Deploying sensitivity labels'
        $result = Deploy-SensitivityLabels -Config $Config -WhatIf:$WhatIfPreference
        if ($result) { $manifest['sensitivityLabels'] = $result }
        Write-LabLog -Message 'Sensitivity labels deployment complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'sensitivityLabels workload is disabled, skipping.' -Level Info
    }

    # 3. DLP
    if ($Config.workloads.dlp.enabled) {
        Write-LabStep -StepName 'DLP' -Description 'Deploying DLP policies'
        $result = Deploy-DLP -Config $Config -WhatIf:$WhatIfPreference
        if ($result) { $manifest['dlp'] = $result }
        Write-LabLog -Message 'DLP deployment complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'dlp workload is disabled, skipping.' -Level Info
    }

    # 4. Retention
    if ($Config.workloads.retention.enabled) {
        Write-LabStep -StepName 'Retention' -Description 'Deploying retention policies and labels'
        $result = Deploy-Retention -Config $Config -WhatIf:$WhatIfPreference
        if ($result) { $manifest['retention'] = $result }
        Write-LabLog -Message 'Retention deployment complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'retention workload is disabled, skipping.' -Level Info
    }

    # 5. eDiscovery
    if ($Config.workloads.eDiscovery.enabled) {
        Write-LabStep -StepName 'EDiscovery' -Description 'Deploying eDiscovery cases'
        $result = Deploy-EDiscovery -Config $Config -WhatIf:$WhatIfPreference
        if ($result) { $manifest['eDiscovery'] = $result }
        Write-LabLog -Message 'eDiscovery deployment complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'eDiscovery workload is disabled, skipping.' -Level Info
    }

    # 6. Communication Compliance
    if ($Config.workloads.communicationCompliance.enabled) {
        Write-LabStep -StepName 'CommunicationCompliance' -Description 'Deploying communication compliance policies'
        $result = Deploy-CommunicationCompliance -Config $Config -WhatIf:$WhatIfPreference
        if ($result) { $manifest['communicationCompliance'] = $result }
        Write-LabLog -Message 'Communication compliance deployment complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'communicationCompliance workload is disabled, skipping.' -Level Info
    }

    # 7. Insider Risk
    if ($Config.workloads.insiderRisk.enabled) {
        Write-LabStep -StepName 'InsiderRisk' -Description 'Deploying insider risk management policies'
        $result = Deploy-InsiderRisk -Config $Config -WhatIf:$WhatIfPreference
        if ($result) { $manifest['insiderRisk'] = $result }
        Write-LabLog -Message 'Insider risk deployment complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'insiderRisk workload is disabled, skipping.' -Level Info
    }

    # 8. Test Data
    if ($Config.workloads.testData.enabled) {
        Write-LabStep -StepName 'TestData' -Description 'Sending test data (emails, files)'
        $result = Send-TestData -Config $Config -WhatIf:$WhatIfPreference
        if ($result) { $manifest['testData'] = $result }
        Write-LabLog -Message 'Test data deployment complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'testData workload is disabled, skipping.' -Level Info
    }

    # Export manifest
    $manifestDir = Join-Path $PSScriptRoot 'manifests'
    if (-not (Test-Path $manifestDir)) {
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $manifestPath = Join-Path $manifestDir "$($Config.prefix)_${timestamp}.json"
    Export-LabManifest -ManifestData ([PSCustomObject]$manifest) -OutputPath $manifestPath
    Write-LabLog -Message "Manifest exported to $manifestPath" -Level Success

    # Summary
    $deployedCount = $manifest.Keys.Count
    Write-LabStep -StepName 'Summary' -Description 'Deployment complete'
    Write-LabLog -Message "Workloads deployed: $deployedCount" -Level Info
    Write-LabLog -Message "Manifest: $manifestPath" -Level Info
    Write-LabLog -Message 'Deploy-Lab finished successfully.' -Level Success
}
catch {
    Write-LabLog -Message "Deploy-Lab failed: $_" -Level Error
    Write-LabLog -Message $_.ScriptStackTrace -Level Error
    throw
}
finally {
    if (-not $SkipAuth) {
        Disconnect-LabServices
    }
    Complete-LabLogging
}
