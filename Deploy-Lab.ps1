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
    $failedWorkloads = @()

    # Helper: deploy a workload with error isolation
    function Invoke-Workload {
        param([string]$Name, [string]$Step, [string]$Description, [scriptblock]$Action)
        Write-LabStep -StepName $Step -Description $Description
        try {
            $result = & $Action
            if ($result) { $manifest[$Name] = $result }
            Write-LabLog -Message "$Step deployment complete." -Level Success
        }
        catch {
            Write-LabLog -Message "$Step FAILED: $_" -Level Error
            $script:failedWorkloads += $Name
        }
    }

    # Deploy workloads in dependency order
    if ($Config.workloads.testUsers.enabled) {
        Invoke-Workload -Name 'testUsers' -Step 'TestUsers' -Description 'Deploying test users' -Action {
            Deploy-TestUsers -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'testUsers workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.sensitivityLabels.enabled) {
        Invoke-Workload -Name 'sensitivityLabels' -Step 'SensitivityLabels' -Description 'Deploying sensitivity labels' -Action {
            Deploy-SensitivityLabels -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'sensitivityLabels workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.dlp.enabled) {
        Invoke-Workload -Name 'dlp' -Step 'DLP' -Description 'Deploying DLP policies' -Action {
            Deploy-DLP -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'dlp workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.retention.enabled) {
        Invoke-Workload -Name 'retention' -Step 'Retention' -Description 'Deploying retention policies' -Action {
            Deploy-Retention -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'retention workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.eDiscovery.enabled) {
        Invoke-Workload -Name 'eDiscovery' -Step 'EDiscovery' -Description 'Deploying eDiscovery cases' -Action {
            Deploy-EDiscovery -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'eDiscovery workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.communicationCompliance.enabled) {
        Invoke-Workload -Name 'communicationCompliance' -Step 'CommunicationCompliance' -Description 'Deploying communication compliance policies' -Action {
            Deploy-CommunicationCompliance -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'communicationCompliance workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.insiderRisk.enabled) {
        Invoke-Workload -Name 'insiderRisk' -Step 'InsiderRisk' -Description 'Deploying insider risk management policies' -Action {
            Deploy-InsiderRisk -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'insiderRisk workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.testData.enabled) {
        Invoke-Workload -Name 'testData' -Step 'TestData' -Description 'Sending test data (emails, files)' -Action {
            Send-TestData -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'testData workload is disabled, skipping.' -Level Info }

    # Export manifest
    $manifestDir = Join-Path $PSScriptRoot 'manifests'
    if (-not (Test-Path $manifestDir)) {
        New-Item -ItemType Directory -Path $manifestDir -Force -WhatIf:$false | Out-Null
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
    if ($failedWorkloads.Count -gt 0) {
        Write-LabLog -Message "FAILED workloads: $($failedWorkloads -join ', '). Re-run to retry." -Level Warning
    }
    else {
        Write-LabLog -Message 'Deploy-Lab finished successfully.' -Level Success
    }
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
