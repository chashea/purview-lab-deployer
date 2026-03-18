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
)

Write-Host ''
Write-Host 'Available profiles:'
foreach ($p in $profiles) {
    Write-Host "  [$($p.Number)] $($p.Name) - $($p.Description)"
}
Write-Host ''

do {
    $profileInput = Read-Host 'Select profile [1/2] (default: 1)'
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

# Test users mode - default to existing (use pre-existing Entra ID users)
$createUsersInput = Read-Host 'Create new test users in Entra ID? [y/N] (default: N)'
if ($createUsersInput -match '^[Yy]') {
    $deployParams['TestUsersMode'] = 'create'
} else {
    $deployParams['TestUsersMode'] = 'existing'
}

& $deployScriptPath @deployParams
