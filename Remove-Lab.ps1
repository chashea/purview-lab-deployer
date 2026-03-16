#Requires -Version 7.0

<#
.SYNOPSIS
    Main teardown orchestrator for purview-lab-deployer.

.DESCRIPTION
    Removes Microsoft Purview lab workloads in reverse dependency order.
    Can use a deployment manifest for precise removal, or fall back to
    config + prefix-based removal.

.PARAMETER ConfigPath
    Path to the lab configuration JSON file.

.PARAMETER ManifestPath
    Optional path to a deployment manifest. When provided, uses manifest
    entries for precise resource removal. Otherwise falls back to
    config + prefix-based removal.

.PARAMETER SkipAuth
    Skip connecting to Exchange Online and Microsoft Graph (for testing).

.EXAMPLE
    ./Remove-Lab.ps1 -ConfigPath configs/full-demo.json

.EXAMPLE
    ./Remove-Lab.ps1 -ConfigPath configs/full-demo.json -ManifestPath manifests/lab_20260316-100000.json

.EXAMPLE
    ./Remove-Lab.ps1 -ConfigPath configs/full-demo.json -Confirm:$false
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ManifestPath,

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
    Write-LabLog -Message 'Remove-Lab started.' -Level Info

    # Load configuration
    Write-LabStep -StepName 'Config' -Description 'Loading lab configuration'
    $Config = Import-LabConfig -ConfigPath $ConfigPath
    Write-LabLog -Message "Lab: $($Config.labName) | Prefix: $($Config.prefix) | Domain: $($Config.domain)" -Level Info

    # Load manifest if provided
    $Manifest = $null
    if ($ManifestPath) {
        Write-LabLog -Message "Loading manifest from $ManifestPath" -Level Info
        $Manifest = Import-LabManifest -ManifestPath $ManifestPath
        Write-LabLog -Message 'Manifest loaded. Using manifest for precise removal.' -Level Info
    }
    else {
        Write-LabLog -Message 'No manifest provided. Falling back to config + prefix-based removal.' -Level Warning
    }

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

    # Remove workloads in reverse dependency order

    # TestData — skip (sent emails cannot be recalled)
    Write-LabStep -StepName 'TestData' -Description 'Test data removal'
    Write-LabLog -Message 'TestData: skipped. Sent emails and uploaded files cannot be recalled.' -Level Warning

    # 1. Insider Risk
    if ($Config.workloads.insiderRisk.enabled) {
        Write-LabStep -StepName 'InsiderRisk' -Description 'Removing insider risk management policies'
        Remove-InsiderRisk -Config $Config -Manifest $Manifest -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Insider risk removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'insiderRisk workload is disabled, skipping.' -Level Info
    }

    # 2. Communication Compliance
    if ($Config.workloads.communicationCompliance.enabled) {
        Write-LabStep -StepName 'CommunicationCompliance' -Description 'Removing communication compliance policies'
        Remove-CommunicationCompliance -Config $Config -Manifest $Manifest -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Communication compliance removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'communicationCompliance workload is disabled, skipping.' -Level Info
    }

    # 3. eDiscovery
    if ($Config.workloads.eDiscovery.enabled) {
        Write-LabStep -StepName 'EDiscovery' -Description 'Removing eDiscovery cases'
        Remove-EDiscovery -Config $Config -Manifest $Manifest -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'eDiscovery removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'eDiscovery workload is disabled, skipping.' -Level Info
    }

    # 4. Retention
    if ($Config.workloads.retention.enabled) {
        Write-LabStep -StepName 'Retention' -Description 'Removing retention policies and labels'
        Remove-Retention -Config $Config -Manifest $Manifest -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Retention removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'retention workload is disabled, skipping.' -Level Info
    }

    # 5. DLP
    if ($Config.workloads.dlp.enabled) {
        Write-LabStep -StepName 'DLP' -Description 'Removing DLP policies'
        Remove-DLP -Config $Config -Manifest $Manifest -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'DLP removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'dlp workload is disabled, skipping.' -Level Info
    }

    # 6. Sensitivity Labels
    if ($Config.workloads.sensitivityLabels.enabled) {
        Write-LabStep -StepName 'SensitivityLabels' -Description 'Removing sensitivity labels'
        Remove-SensitivityLabels -Config $Config -Manifest $Manifest -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Sensitivity labels removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'sensitivityLabels workload is disabled, skipping.' -Level Info
    }

    # 7. Test Users
    if ($Config.workloads.testUsers.enabled) {
        Write-LabStep -StepName 'TestUsers' -Description 'Removing test users'
        Remove-TestUsers -Config $Config -Manifest $Manifest -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Test users removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'testUsers workload is disabled, skipping.' -Level Info
    }

    # Summary
    Write-LabStep -StepName 'Summary' -Description 'Teardown complete'
    Write-LabLog -Message 'Remove-Lab finished successfully.' -Level Success
}
catch {
    Write-LabLog -Message "Remove-Lab failed: $_" -Level Error
    Write-LabLog -Message $_.ScriptStackTrace -Level Error
    throw
}
finally {
    if (-not $SkipAuth) {
        Disconnect-LabServices
    }
    Complete-LabLogging
}
