#!/usr/bin/env pwsh
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

# Import interactive prompting module
Import-Module (Join-Path $PSScriptRoot 'modules' 'Interactive.psm1') -Force

# Cloud selection
$cloud = Request-LabCloud

# Profile selection
$selectedLabProfile = Request-LabProfile

# Tenant ID
$tenantId = $null
if (-not $SkipAuth) {
    $tenantId = Request-LabTenantId
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
