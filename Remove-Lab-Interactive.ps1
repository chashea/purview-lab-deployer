#Requires -Version 7.0

<#
.SYNOPSIS
    Interactive teardown entrypoint for purview-lab-deployer.

.DESCRIPTION
    Prompts for cloud, profile, tenant ID, and optional manifest path,
    then invokes Remove-Lab.ps1.

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
    [string]$ManifestPath,

    [Parameter()]
    [switch]$WhatIf,

    [Parameter()]
    [switch]$SkipAuth
)

$ErrorActionPreference = 'Stop'

# Cloud selection
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

# Profile selection
$profiles = @(
    @{ Number = 1; Name = 'basic-lab'; Description = 'Basic demo lab' }
    @{ Number = 2; Name = 'shadow-ai'; Description = 'Shadow AI demo' }
    @{ Number = 3; Name = 'copilot-dlp'; Description = 'Copilot DLP guardrails demo' }
)

Write-Host ''
Write-Host 'Available profiles:'
foreach ($p in $profiles) {
    Write-Host "  [$($p.Number)] $($p.Name) - $($p.Description)"
}
Write-Host ''

do {
    $profileInput = Read-Host 'Select profile [1/2/3] (default: 1)'
    if ([string]::IsNullOrWhiteSpace($profileInput)) {
        $selectedLabProfile = 'basic-lab'
    }
    else {
        $match = $profiles | Where-Object { $_.Number -eq [int]$profileInput -or $_.Name -eq $profileInput.Trim() }
        if ($match) {
            $selectedLabProfile = $match.Name
        }
        else {
            Write-Warning "Invalid selection '$profileInput'."
            $selectedLabProfile = $null
        }
    }
} while (-not $selectedLabProfile)

# Tenant ID
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

# Manifest (optional)
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
    LabProfile = $selectedLabProfile
    Cloud   = $cloud
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

Write-Host "Starting remove with cloud='$cloud' profile='$selectedLabProfile'..."
& $removeScriptPath @removeParams
