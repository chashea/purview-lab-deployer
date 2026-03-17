#Requires -Version 7.0

<#
.SYNOPSIS
    Interactive teardown entrypoint for purview-lab-deployer.

.DESCRIPTION
    Prompts for cloud profile, tenant ID, config path, and optional manifest
    path, then invokes Remove-Lab.ps1 with the selected values.

.PARAMETER ConfigPath
    Optional path to config file. If omitted, defaults to configs/<cloud>/full-demo.json.

.PARAMETER ManifestPath
    Optional manifest path. If omitted, Remove-Lab.ps1 falls back to config/prefix-based removal.

.PARAMETER WhatIf
    Passes WhatIf to Remove-Lab.ps1.

.PARAMETER SkipAuth
    Passes SkipAuth to Remove-Lab.ps1.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$ManifestPath,

    [Parameter()]
    [switch]$WhatIf,

    [Parameter()]
    [switch]$SkipAuth
)

$ErrorActionPreference = 'Stop'

$defaultCloud = if ([string]::IsNullOrWhiteSpace($env:PURVIEW_CLOUD)) { 'commercial' } else { $env:PURVIEW_CLOUD.ToLowerInvariant() }
$allowedClouds = @('commercial', 'gcc')

do {
    $cloudInput = Read-Host "Purview cloud [commercial/gcc] (default: $defaultCloud)"
    if ([string]::IsNullOrWhiteSpace($cloudInput)) {
        $cloud = $defaultCloud
    }
    else {
        $cloud = $cloudInput.Trim().ToLowerInvariant()
    }

    if ($allowedClouds -notcontains $cloud) {
        Write-Warning "Invalid cloud '$cloud'. Enter 'commercial' or 'gcc'."
        $cloud = $null
    }
} while (-not $cloud)

$tenantId = $null
if (-not $SkipAuth) {
    do {
        $defaultTenant = $env:PURVIEW_TENANT_ID
        $tenantPrompt = if ([string]::IsNullOrWhiteSpace($defaultTenant)) {
            'Tenant ID (GUID)'
        }
        else {
            "Tenant ID (GUID) (default: $defaultTenant)"
        }

        $tenantInput = Read-Host $tenantPrompt
        if ([string]::IsNullOrWhiteSpace($tenantInput)) {
            $tenantId = $defaultTenant
        }
        else {
            $tenantId = $tenantInput.Trim()
        }

        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            Write-Warning 'Tenant ID is required unless -SkipAuth is used.'
        }
    } while ([string]::IsNullOrWhiteSpace($tenantId))
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $defaultConfigPath = Join-Path $PSScriptRoot "configs/$cloud/full-demo.json"
    $configInput = Read-Host "Config path (default: $defaultConfigPath)"
    if ([string]::IsNullOrWhiteSpace($configInput)) {
        $ConfigPath = $defaultConfigPath
    }
    else {
        $ConfigPath = $configInput.Trim()
    }
}

if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
    throw "Config file not found: $ConfigPath"
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $defaultManifestDir = Join-Path $PSScriptRoot "manifests/$cloud"
    $manifestInput = Read-Host "Manifest path (optional, blank uses config/prefix fallback) [suggested dir: $defaultManifestDir]"
    if (-not [string]::IsNullOrWhiteSpace($manifestInput)) {
        $ManifestPath = $manifestInput.Trim()
    }
}

if (-not [string]::IsNullOrWhiteSpace($ManifestPath) -and -not (Test-Path -Path $ManifestPath -PathType Leaf)) {
    throw "Manifest file not found: $ManifestPath"
}

$removeScriptPath = Join-Path $PSScriptRoot 'Remove-Lab.ps1'
$removeParams = @{
    ConfigPath = $ConfigPath
    Cloud      = $cloud
}

if ($WhatIf) {
    $removeParams['WhatIf'] = $true
}

if ($SkipAuth) {
    $removeParams['SkipAuth'] = $true
}
else {
    $removeParams['TenantId'] = $tenantId
}

if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $removeParams['ManifestPath'] = $ManifestPath
}

Write-Host "Starting remove with cloud='$cloud' config='$ConfigPath'..."
& $removeScriptPath @removeParams
