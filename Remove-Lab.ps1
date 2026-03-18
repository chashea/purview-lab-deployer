#Requires -Version 7.0

<#
.SYNOPSIS
    Main teardown orchestrator for purview-lab-deployer.

.DESCRIPTION
    Removes Microsoft Purview lab workloads in reverse dependency order.
    Can use a deployment manifest for precise removal, or fall back to
    config + prefix-based removal.

.PARAMETER ConfigPath
    Path to the lab configuration JSON file. Optional when -LabProfile is used.

.PARAMETER LabProfile
    Deployment profile name. Resolves to a config file under configs/<cloud>/.
    Available profiles: full-lab, shadow-ai.

.PARAMETER ManifestPath
    Optional path to a deployment manifest. When provided, uses manifest
    entries for precise resource removal. Otherwise falls back to
    config + prefix-based removal.

.PARAMETER SkipAuth
    Skip connecting to Exchange Online and Microsoft Graph (for testing).

.PARAMETER TenantId
    Microsoft Entra tenant ID. Defaults to environment variable PURVIEW_TENANT_ID.
    Required unless -SkipAuth is specified.

.PARAMETER Cloud
    Cloud profile to use (`commercial` or `gcc`). If omitted, uses config value.

.EXAMPLE
    ./Remove-Lab.ps1 -Cloud commercial -LabProfile full-lab

.EXAMPLE
    ./Remove-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -Confirm:$false

.EXAMPLE
    ./Remove-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -ManifestPath manifests/lab_20260316-100000.json
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [Parameter()]
    [ValidateSet('full-lab', 'shadow-ai')]
    [string]$LabProfile,

    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ManifestPath,

    [Parameter()]
    [switch]$SkipAuth,

    [Parameter()]
    [string]$TenantId = $env:PURVIEW_TENANT_ID,

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = $env:PURVIEW_CLOUD
)

$ErrorActionPreference = 'Stop'

# Profile-to-config resolution
$profileConfigMap = @{
    'full-lab'  = 'full-demo.json'
    'shadow-ai' = 'shadow-ai-demo.json'
}

if (-not [string]::IsNullOrWhiteSpace($LabProfile) -and -not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    throw 'Specify either -LabProfile or -ConfigPath, not both.'
}

if (-not [string]::IsNullOrWhiteSpace($LabProfile)) {
    $resolvedCloud = if ([string]::IsNullOrWhiteSpace($Cloud)) { 'commercial' } else { $Cloud }
    $configFileName = $profileConfigMap[$LabProfile]
    $ConfigPath = Join-Path $PSScriptRoot "configs/$resolvedCloud/$configFileName"
    if (-not (Test-Path $ConfigPath -PathType Leaf)) {
        throw "Profile '$LabProfile' config not found for cloud '$resolvedCloud': $ConfigPath"
    }
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    throw 'Either -LabProfile or -ConfigPath is required.'
}

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
    $resolvedCloud = Resolve-LabCloud -Cloud $Cloud -Config $Config
    $capabilityProfile = Import-LabCloudProfile -Cloud $resolvedCloud -RepositoryRoot $PSScriptRoot
    Write-LabLog -Message "Lab: $($Config.labName) | Prefix: $($Config.prefix) | Domain: $($Config.domain) | Cloud: $resolvedCloud" -Level Info

    # Warn on cloud capability differences for teardown context
    $compatibility = Test-LabWorkloadCompatibility -Config $Config -CapabilityProfile $capabilityProfile -Operation Remove
    foreach ($warning in $compatibility.warnings) {
        Write-LabLog -Message $warning -Level Warning
    }

    # Load manifest if provided
    $Manifest = $null
    if ($ManifestPath) {
        Write-LabLog -Message "Loading manifest from $ManifestPath" -Level Info
        $Manifest = Import-LabManifest -ManifestPath $ManifestPath
        Write-LabLog -Message 'Manifest loaded. Using manifest for precise removal.' -Level Info
    }
    else {
        $defaultManifestDir = Join-Path (Join-Path $PSScriptRoot 'manifests') $resolvedCloud
        Write-LabLog -Message "No manifest provided. Falling back to config + prefix-based removal. Cloud manifest folder: $defaultManifestDir" -Level Warning
    }

    function Get-WorkloadManifest {
        param(
            [Parameter(Mandatory)]
            [string]$WorkloadName
        )

        if ($Manifest -and $Manifest.data -and $Manifest.data.PSObject.Properties[$WorkloadName]) {
            return $Manifest.data.$WorkloadName
        }

        return $null
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
        if ([string]::IsNullOrWhiteSpace($TenantId)) {
            throw 'TenantId is required when authentication is enabled. Use -TenantId or set PURVIEW_TENANT_ID.'
        }

        Write-LabStep -StepName 'Auth' -Description 'Connecting to cloud services'
        Connect-LabServices -TenantId $TenantId
        Write-LabLog -Message 'Connected to Exchange Online and Microsoft Graph.' -Level Success

        $resolvedDomain = Resolve-LabTenantDomain -ConfiguredDomain $Config.domain
        if (-not [string]::Equals($resolvedDomain, [string]$Config.domain, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-LabLog -Message "Configured domain '$($Config.domain)' is not verified in this tenant. Using '$resolvedDomain' for teardown lookups." -Level Warning
            $Config.domain = $resolvedDomain
        }
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
        Remove-InsiderRisk -Config $Config -Manifest (Get-WorkloadManifest -WorkloadName 'insiderRisk') -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Insider risk removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'insiderRisk workload is disabled, skipping.' -Level Info
    }

    # 2. Communication Compliance
    if ($Config.workloads.communicationCompliance.enabled) {
        Write-LabStep -StepName 'CommunicationCompliance' -Description 'Removing communication compliance policies'
        Remove-CommunicationCompliance -Config $Config -Manifest (Get-WorkloadManifest -WorkloadName 'communicationCompliance') -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Communication compliance removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'communicationCompliance workload is disabled, skipping.' -Level Info
    }

    # 3. eDiscovery
    if ($Config.workloads.eDiscovery.enabled) {
        Write-LabStep -StepName 'EDiscovery' -Description 'Removing eDiscovery cases'
        Remove-EDiscovery -Config $Config -Manifest (Get-WorkloadManifest -WorkloadName 'eDiscovery') -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'eDiscovery removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'eDiscovery workload is disabled, skipping.' -Level Info
    }

    # 4. Retention
    if ($Config.workloads.retention.enabled) {
        Write-LabStep -StepName 'Retention' -Description 'Removing retention policies and labels'
        Remove-Retention -Config $Config -Manifest (Get-WorkloadManifest -WorkloadName 'retention') -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Retention removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'retention workload is disabled, skipping.' -Level Info
    }

    # 5. DLP
    if ($Config.workloads.dlp.enabled) {
        Write-LabStep -StepName 'DLP' -Description 'Removing DLP policies'
        Remove-DLP -Config $Config -Manifest (Get-WorkloadManifest -WorkloadName 'dlp') -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'DLP removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'dlp workload is disabled, skipping.' -Level Info
    }

    # 6. Custom Sensitive Info Types
    if ($Config.workloads.PSObject.Properties['customSensitiveInfoTypes'] -and $Config.workloads.customSensitiveInfoTypes.enabled) {
        Write-LabStep -StepName 'CustomSensitiveInfoTypes' -Description 'Removing custom sensitive information types'
        Remove-CustomSensitiveInfoTypes -Config $Config -Manifest (Get-WorkloadManifest -WorkloadName 'customSensitiveInfoTypes') -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Custom sensitive info types removal complete.' -Level Success
    }

    # 7. Sensitivity Labels
    if ($Config.workloads.sensitivityLabels.enabled) {
        Write-LabStep -StepName 'SensitivityLabels' -Description 'Removing sensitivity labels'
        Remove-SensitivityLabels -Config $Config -Manifest (Get-WorkloadManifest -WorkloadName 'sensitivityLabels') -WhatIf:$WhatIfPreference
        Write-LabLog -Message 'Sensitivity labels removal complete.' -Level Success
    }
    else {
        Write-LabLog -Message 'sensitivityLabels workload is disabled, skipping.' -Level Info
    }

    # 8. Test Users
    if ($Config.workloads.testUsers.enabled) {
        Write-LabStep -StepName 'TestUsers' -Description 'Removing test users'
        Remove-TestUsers -Config $Config -Manifest (Get-WorkloadManifest -WorkloadName 'testUsers') -WhatIf:$WhatIfPreference
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
