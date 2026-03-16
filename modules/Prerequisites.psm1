#Requires -Version 7.0

<#
.SYNOPSIS
    Prerequisites, authentication, and configuration module for purview-lab-deployer.
#>

$script:RequiredModules = @(
    'ExchangeOnlineManagement'
    'Microsoft.Graph.Authentication'
    'Microsoft.Graph.Users'
    'Microsoft.Graph.Groups'
)

function Test-LabPrerequisites {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $allPassed = $true

    # Check PowerShell 7+
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Warning "PowerShell 7+ is required. Current version: $($PSVersionTable.PSVersion)"
        $allPassed = $false
    }
    else {
        Write-Verbose "PowerShell $($PSVersionTable.PSVersion) detected."
    }

    # Check required modules
    foreach ($moduleName in $script:RequiredModules) {
        $module = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
        if (-not $module) {
            Write-Warning "Required module not installed: $moduleName"
            $allPassed = $false
        }
        else {
            Write-Verbose "Module found: $moduleName ($($module.Version))"
        }
    }

    return $allPassed
}

function Connect-LabServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId
    )

    $graphScopes = @(
        'User.ReadWrite.All'
        'Group.ReadWrite.All'
        'Mail.Send'
        'Policy.ReadWrite.ConditionalAccess'
    )

    Write-Verbose "Connecting to Security & Compliance PowerShell (tenant: $TenantId)..."
    Connect-IPPSSession -CommandName * -WarningAction SilentlyContinue

    Write-Verbose "Connecting to Microsoft Graph (tenant: $TenantId)..."
    Connect-MgGraph -TenantId $TenantId -Scopes $graphScopes -NoWelcome -UseDeviceCode
}

function Disconnect-LabServices {
    [CmdletBinding()]
    param()

    Write-Verbose 'Disconnecting from Security & Compliance PowerShell...'
    try {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Exchange Online disconnect: $_"
    }

    Write-Verbose 'Disconnecting from Microsoft Graph...'
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Microsoft Graph disconnect: $_"
    }
}

function Import-LabConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ConfigPath
    )

    $raw = Get-Content -Path $ConfigPath -Raw
    $config = $raw | ConvertFrom-Json

    # Validate required fields
    $requiredFields = @('labName', 'prefix', 'domain')
    foreach ($field in $requiredFields) {
        if (-not $config.PSObject.Properties[$field]) {
            throw "Configuration is missing required field: '$field'"
        }
        if ([string]::IsNullOrWhiteSpace($config.$field)) {
            throw "Configuration field '$field' must not be empty."
        }
    }

    # Note: if a _schema.json file exists alongside the config, JSON Schema
    # validation could be added in the future.
    $schemaPath = Join-Path (Split-Path $ConfigPath) '_schema.json'
    if (Test-Path $schemaPath) {
        Write-Verbose "Schema file found at $schemaPath. Schema validation is not yet implemented."
    }

    return $config
}

function Export-LabManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ManifestData,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # Add deployment timestamp
    $manifest = [ordered]@{
        generatedAt = (Get-Date -Format 'o')
        data        = $ManifestData
    }

    $json = $manifest | ConvertTo-Json -Depth 10
    $json | Set-Content -Path $OutputPath -Encoding utf8

    Write-Verbose "Manifest written to $OutputPath"
}

function Import-LabManifest {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ManifestPath
    )

    $raw = Get-Content -Path $ManifestPath -Raw
    $manifest = $raw | ConvertFrom-Json

    return $manifest
}

Export-ModuleMember -Function @(
    'Test-LabPrerequisites'
    'Connect-LabServices'
    'Disconnect-LabServices'
    'Import-LabConfig'
    'Export-LabManifest'
    'Import-LabManifest'
)
