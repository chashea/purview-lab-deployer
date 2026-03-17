#Requires -Version 7.0

<#
.SYNOPSIS
    Publish sensitivity labels for GCC tenants.

.DESCRIPTION
    Loads label definitions from a GCC config file and creates/updates the
    managed label publication policy (`<prefix>-Sensitivity-Labels-Publish`)
    without running the full deployment pipeline.

.PARAMETER ConfigPath
    Path to a GCC config JSON. Defaults to configs/gcc/full-demo.json.

.PARAMETER TenantId
    Microsoft Entra tenant ID. Defaults to PURVIEW_TENANT_ID.

.PARAMETER SkipAuth
    Skip connecting to services (for testing).

.EXAMPLE
    ./Publish-Labels-GCC.ps1 -TenantId <tenant-guid>

.EXAMPLE
    ./Publish-Labels-GCC.ps1 -ConfigPath configs/gcc/full-demo.json -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'configs/gcc/full-demo.json'),

    [Parameter()]
    [string]$TenantId = $env:PURVIEW_TENANT_ID,

    [Parameter()]
    [switch]$SkipAuth,

    [Parameter()]
    [ValidateSet('gcc')]
    [string]$Cloud = 'gcc'
)

$ErrorActionPreference = 'Stop'

foreach ($mod in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'modules') -Filter '*.psm1')) {
    Import-Module $mod.FullName -Force
}

try {
    Initialize-LabLogging -Prefix 'PurviewLab'
    Write-LabLog -Message 'Publish-Labels-GCC started.' -Level Info

    Write-LabStep -StepName 'Config' -Description 'Loading GCC configuration'
    $Config = Import-LabConfig -ConfigPath $ConfigPath
    $resolvedCloud = Resolve-LabCloud -Cloud $Cloud -Config $Config
    if ($resolvedCloud -ne 'gcc') {
        throw "Publish-Labels-GCC supports only GCC configs. Resolved cloud: '$resolvedCloud'."
    }

    Write-LabLog -Message "Lab: $($Config.labName) | Prefix: $($Config.prefix) | Cloud: $resolvedCloud" -Level Info

    Write-LabStep -StepName 'Prerequisites' -Description 'Validating prerequisites'
    if (-not (Test-LabPrerequisites)) {
        throw 'Prerequisites check failed.'
    }

    if (-not $SkipAuth) {
        if ([string]::IsNullOrWhiteSpace($TenantId)) {
            throw 'TenantId is required when authentication is enabled. Use -TenantId or set PURVIEW_TENANT_ID.'
        }

        Write-LabStep -StepName 'Auth' -Description 'Connecting to cloud services'
        Connect-LabServices -TenantId $TenantId
        Write-LabLog -Message 'Connected to Exchange Online and Microsoft Graph.' -Level Success
    }
    else {
        Write-LabLog -Message 'Skipping authentication (-SkipAuth).' -Level Warning
    }

    Write-LabStep -StepName 'PublishLabels' -Description 'Publishing sensitivity labels'
    $result = Publish-SensitivityLabels -Config $Config -WhatIf:$WhatIfPreference
    if ($result -and $result.publicationPolicy) {
        Write-LabLog -Message "Publication policy: $($result.publicationPolicy.name)" -Level Success
        Write-LabLog -Message "Published labels count: $($result.publishedLabels.Count)" -Level Info
    }
    else {
        Write-LabLog -Message 'No publication policy changes were made.' -Level Warning
    }

    Write-LabLog -Message 'Publish-Labels-GCC finished.' -Level Success
}
catch {
    Write-LabLog -Message "Publish-Labels-GCC failed: $_" -Level Error
    Write-LabLog -Message $_.ScriptStackTrace -Level Error
    throw
}
finally {
    if (-not $SkipAuth) {
        Disconnect-LabServices
    }
    Complete-LabLogging
}
