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
    'Microsoft.Graph.Identity.SignIns'
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
        'Organization.Read.All'
        'Policy.ReadWrite.ConditionalAccess'
        'eDiscovery.ReadWrite.All'
    )

    Write-Verbose "Connecting to Security & Compliance PowerShell (tenant: $TenantId)..."
    Connect-IPPSSession -CommandName * -WarningAction SilentlyContinue -ErrorAction Stop

    Write-Verbose "Connecting to Microsoft Graph (tenant: $TenantId)..."
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Connect-MgGraph -TenantId $TenantId -Scopes $graphScopes -NoWelcome -ErrorAction Stop

    $graphContext = Get-MgContext
    if (-not $graphContext -or [string]::IsNullOrWhiteSpace($graphContext.Account)) {
        throw 'Microsoft Graph authentication did not produce a usable context.'
    }
}

function Resolve-LabTenantDomain {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ConfiguredDomain
    )

    $configured = $ConfiguredDomain.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($configured)) {
        throw 'Configured domain is empty.'
    }

    try {
        $org = Invoke-MgGraphRequest -Method GET -Uri '/v1.0/organization?$select=verifiedDomains' -ErrorAction Stop
        $verifiedDomains = @()
        if ($org.value -and $org.value.Count -gt 0 -and $org.value[0].verifiedDomains) {
            $verifiedDomains = @($org.value[0].verifiedDomains)
        }

        $verifiedNames = @()
        foreach ($d in $verifiedDomains) {
            if ($d.name) { $verifiedNames += [string]$d.name }
        }

        if ($verifiedNames -contains $configured) {
            return $configured
        }

        $defaultDomain = $null
        foreach ($d in $verifiedDomains) {
            if ($d.isDefault -eq $true -and $d.name) {
                $defaultDomain = [string]$d.name
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($defaultDomain) -and $verifiedNames.Count -gt 0) {
            $defaultDomain = [string]$verifiedNames[0]
        }

        if (-not [string]::IsNullOrWhiteSpace($defaultDomain)) {
            return $defaultDomain.ToLowerInvariant()
        }
    }
    catch {
        Write-Verbose "Unable to resolve verified domains from Graph organization: $($_.Exception.Message)"
    }

    $context = Get-MgContext
    if ($context -and -not [string]::IsNullOrWhiteSpace($context.Account) -and $context.Account.Contains('@')) {
        $accountDomain = $context.Account.Split('@')[-1].ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($accountDomain)) {
            return $accountDomain
        }
    }

    return $configured
}

function Get-LabUserByIdentity {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Identity,

        [Parameter(Mandatory)]
        [string]$DefaultDomain
    )

    $trimmedIdentity = $Identity.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedIdentity)) {
        throw 'User identity cannot be empty.'
    }

    $candidateUpn = if ($trimmedIdentity.Contains('@')) {
        $trimmedIdentity
    }
    else {
        "$trimmedIdentity@$DefaultDomain"
    }

    $escapedCandidateUpn = $candidateUpn.Replace("'", "''")
    $byUpn = Get-MgUser -Filter "userPrincipalName eq '$escapedCandidateUpn'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($byUpn) {
        return $byUpn
    }

    if (-not $trimmedIdentity.Contains('@')) {
        $escapedNickname = $trimmedIdentity.Replace("'", "''")
        $byNickname = Get-MgUser -Filter "mailNickname eq '$escapedNickname'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($byNickname) {
            return $byNickname
        }
    }

    return $null
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

function Resolve-LabCloud {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Cloud,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $validClouds = @('commercial', 'gcc')
    $resolvedCloud = $null

    if (-not [string]::IsNullOrWhiteSpace($Cloud)) {
        $resolvedCloud = $Cloud.Trim().ToLowerInvariant()
    }
    elseif ($Config.PSObject.Properties['cloud'] -and -not [string]::IsNullOrWhiteSpace([string]$Config.cloud)) {
        $resolvedCloud = ([string]$Config.cloud).Trim().ToLowerInvariant()
    }
    else {
        $resolvedCloud = 'commercial'
    }

    if ($validClouds -notcontains $resolvedCloud) {
        throw "Unsupported cloud '$resolvedCloud'. Supported values: commercial, gcc."
    }

    return $resolvedCloud
}

function Import-LabCloudProfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Cloud,

        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    $profilePath = Join-Path $RepositoryRoot "profiles/$Cloud/capabilities.json"
    if (-not (Test-Path $profilePath -PathType Leaf)) {
        throw "Cloud capability profile not found: $profilePath"
    }

    $raw = Get-Content -Path $profilePath -Raw
    return ($raw | ConvertFrom-Json)
}

function Test-LabWorkloadCompatibility {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [PSCustomObject]$CapabilityProfile,

        [Parameter()]
        [ValidateSet('Deploy', 'Remove')]
        [string]$Operation = 'Deploy'
    )

    $warnings = [System.Collections.Generic.List[string]]::new()
    $blockers = [System.Collections.Generic.List[string]]::new()

    if (-not $Config.PSObject.Properties['workloads']) {
        return [PSCustomObject]@{
            warnings = $warnings.ToArray()
            blockers = $blockers.ToArray()
        }
    }

    foreach ($workloadProperty in $Config.workloads.PSObject.Properties) {
        $workloadName = $workloadProperty.Name
        $workloadConfig = $workloadProperty.Value

        if (-not $workloadConfig -or -not $workloadConfig.PSObject.Properties['enabled'] -or -not [bool]$workloadConfig.enabled) {
            continue
        }

        $capability = $null
        if ($CapabilityProfile.PSObject.Properties['workloads'] -and $CapabilityProfile.workloads.PSObject.Properties[$workloadName]) {
            $capability = $CapabilityProfile.workloads.$workloadName
        }

        if (-not $capability) {
            $warnings.Add("No capability metadata found for workload '$workloadName' in profile '$($CapabilityProfile.cloud)'.")
            continue
        }

        $status = 'available'
        if ($capability.PSObject.Properties['status'] -and -not [string]::IsNullOrWhiteSpace([string]$capability.status)) {
            $status = ([string]$capability.status).Trim().ToLowerInvariant()
        }

        $note = ''
        if ($capability.PSObject.Properties['note'] -and -not [string]::IsNullOrWhiteSpace([string]$capability.note)) {
            $note = [string]$capability.note
        }

        switch ($status) {
            'available' {
                continue
            }
            'limited' {
                $warnings.Add("Workload '$workloadName' is marked limited for cloud '$($CapabilityProfile.cloud)'. $note")
            }
            'delayed' {
                $warnings.Add("Workload '$workloadName' may have delayed feature rollout for cloud '$($CapabilityProfile.cloud)'. $note")
            }
            'unavailable' {
                $message = "Workload '$workloadName' is marked unavailable for cloud '$($CapabilityProfile.cloud)'. $note"
                if ($Operation -eq 'Deploy') {
                    $blockers.Add($message)
                }
                else {
                    $warnings.Add($message)
                }
            }
            default {
                $warnings.Add("Workload '$workloadName' has unknown capability status '$status' for cloud '$($CapabilityProfile.cloud)'.")
            }
        }
    }

    return [PSCustomObject]@{
        warnings = $warnings.ToArray()
        blockers = $blockers.ToArray()
    }
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
    'Resolve-LabTenantDomain'
    'Get-LabUserByIdentity'
    'Disconnect-LabServices'
    'Import-LabConfig'
    'Resolve-LabCloud'
    'Import-LabCloudProfile'
    'Test-LabWorkloadCompatibility'
    'Export-LabManifest'
    'Import-LabManifest'
)
