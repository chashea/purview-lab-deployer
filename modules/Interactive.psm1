#Requires -Version 7.0

<#
.SYNOPSIS
    Shared interactive prompting functions for purview-lab-deployer.
#>

function Request-LabCloud {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$DefaultCloud
    )

    if ([string]::IsNullOrWhiteSpace($DefaultCloud)) {
        $DefaultCloud = if ([string]::IsNullOrWhiteSpace($env:PURVIEW_CLOUD)) { 'commercial' } else { $env:PURVIEW_CLOUD.ToLowerInvariant() }
    }

    $allowedClouds = @('commercial', 'gcc')

    do {
        $cloudInput = Read-Host "Purview cloud [commercial/gcc] (default: $DefaultCloud)"
        if ([string]::IsNullOrWhiteSpace($cloudInput)) {
            $cloud = $DefaultCloud
        }
        else {
            $cloud = $cloudInput.Trim().ToLowerInvariant()
        }

        if ($allowedClouds -notcontains $cloud) {
            Write-Warning "Invalid cloud '$cloud'. Enter 'commercial' or 'gcc'."
            $cloud = $null
        }
    } while (-not $cloud)

    return $cloud
}

function Request-LabProfile {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $profiles = @(
        @{ Number = 1; Name = 'basic-lab'; Description = 'Basic demo lab' }
        @{ Number = 2; Name = 'shadow-ai'; Description = 'Shadow AI demo' }
        @{ Number = 3; Name = 'copilot-dlp'; Description = 'Copilot DLP guardrails demo' }
        @{ Number = 4; Name = 'foundry'; Description = 'Microsoft AI Foundry agents' }
    )

    $profileNumbers = ($profiles | ForEach-Object { $_.Number }) -join '/'

    Write-Host ''
    Write-Host 'Available profiles:'
    foreach ($p in $profiles) {
        Write-Host "  [$($p.Number)] $($p.Name) - $($p.Description)"
    }
    Write-Host ''

    do {
        $profileInput = Read-Host "Select profile [$profileNumbers] (default: 1)"
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

    return $selectedLabProfile
}

function Request-LabTenantId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $tenantId = $null
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

    return $tenantId
}

Export-ModuleMember -Function @(
    'Request-LabCloud'
    'Request-LabProfile'
    'Request-LabTenantId'
)
