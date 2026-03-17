#Requires -Version 7.0

<#
.SYNOPSIS
    Interactive deployment entrypoint for purview-lab-deployer.

.DESCRIPTION
    Prompts for cloud profile and tenant ID, then invokes Deploy-Lab.ps1 with
    the selected values. Designed for first-time or manual deployments.

.PARAMETER ConfigPath
    Optional path to config file. If omitted, defaults to configs/<cloud>/full-demo.json.

.PARAMETER WhatIf
    Passes WhatIf to Deploy-Lab.ps1.

.PARAMETER SkipAuth
    Passes SkipAuth to Deploy-Lab.ps1.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

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

$deployScriptPath = Join-Path $PSScriptRoot 'Deploy-Lab.ps1'
$deployParams = @{
    ConfigPath = $ConfigPath
    Cloud      = $cloud
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

Write-Host "Starting deploy with cloud='$cloud' config='$ConfigPath'..."
& $deployScriptPath @deployParams
