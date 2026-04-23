#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Interactive deployment entrypoint for purview-lab-deployer.

.DESCRIPTION
    Prompts for cloud, profile, and tenant ID, then invokes Deploy-Lab.ps1.

.PARAMETER WhatIf
    Passes WhatIf to Deploy-Lab.ps1.

.PARAMETER SkipAuth
    Passes SkipAuth to Deploy-Lab.ps1.
#>

[CmdletBinding()]
param(
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

$deployScriptPath = Join-Path $PSScriptRoot 'Deploy-Lab.ps1'
$deployParams = @{
    LabProfile = $selectedLabProfile
    Cloud   = $cloud
}

if ($WhatIf) {
    $deployParams['WhatIf'] = $true
}

if ($SkipAuth) {
    $deployParams['SkipAuth'] = $true
}
else {
    $deployParams['TenantId'] = $tenantId
}

Write-Host "Starting deploy with cloud='$cloud' profile='$selectedLabProfile'..."

& $deployScriptPath @deployParams
