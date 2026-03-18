#Requires -Version 7.0

<#
.SYNOPSIS
    App Governance and Cloud Discovery workload module for purview-lab-deployer.
    Uses the Microsoft Defender for Cloud Apps (MDCA) REST API to tag AI apps,
    create discovery policies, and create session policies.
    OAuth app governance policy creation is not API-supported and is logged as a manual step.
#>

function Deploy-AppGovernance {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $appGovConfig = $Config.workloads.appGovernance
    $prefix = $Config.prefix

    $result = @{
        taggedApps        = @()
        discoveryPolicies = @()
        sessionPolicies   = @()
        manualSteps       = @()
    }

    # Resolve MDCA connection
    $cloud = if ($Config.PSObject.Properties['cloud'] -and -not [string]::IsNullOrWhiteSpace([string]$Config.cloud)) {
        [string]$Config.cloud
    } else { 'commercial' }

    $portalUrl = Get-MdcaPortalUrl -Cloud $cloud -Config $Config
    Write-LabLog -Message "MDCA portal URL: $portalUrl" -Level Info

    $mdcaToken = $null
    if (-not $WhatIfPreference) {
        try {
            $tenantId = if ($env:PURVIEW_TENANT_ID) { $env:PURVIEW_TENANT_ID }
                        elseif ($Config.PSObject.Properties['tenantId']) { [string]$Config.tenantId }
                        else { (Get-MgContext).TenantId }

            $mdcaToken = Connect-LabMdca -PortalUrl $portalUrl -TenantId $tenantId
            Write-LabLog -Message 'MDCA API token acquired.' -Level Success
        }
        catch {
            Write-LabLog -Message "MDCA API authentication failed: $($_.Exception.Message). AI app tagging, discovery policies, and session policies will be skipped." -Level Warning
            Write-ManualSteps -Config $Config -Result $result
            return $result
        }
    }

    # --- 1. Tag AI apps in cloud app catalog ---
    if ($appGovConfig.PSObject.Properties['aiApps'] -and $appGovConfig.aiApps.Count -gt 0) {
        foreach ($app in $appGovConfig.aiApps) {
            $appName = $app.name
            $targetTag = if ($app.PSObject.Properties['tag'] -and $app.tag) { $app.tag } else { 'unsanctioned' }

            try {
                if ($PSCmdlet.ShouldProcess($appName, "Tag as $targetTag in MDCA catalog")) {
                    $catalogApps = Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint 'discovery/discovered_apps/' -Method POST `
                        -Body @{
                            filters = @{
                                appName = @{ eq = @($appName) }
                            }
                            limit = 5
                        }

                    $matchedApp = $null
                    if ($catalogApps -and $catalogApps.data -and $catalogApps.data.Count -gt 0) {
                        $matchedApp = $catalogApps.data | Select-Object -First 1
                    }

                    if (-not $matchedApp) {
                        Write-LabLog -Message "App '$appName' not found in MDCA catalog. It may appear after Cloud Discovery data is ingested." -Level Warning
                        $result.taggedApps += @{
                            name   = $appName
                            tag    = $targetTag
                            status = 'not_found'
                        }
                        continue
                    }

                    $appId = $matchedApp.appId
                    $tagValue = switch ($targetTag) {
                        'unsanctioned' { 1 }
                        'sanctioned'   { 0 }
                        'monitored'    { 2 }
                        default        { 1 }
                    }

                    Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint "discovery/discovered_apps/tag/" -Method POST `
                        -Body @{
                            appIds = @($appId)
                            tag    = $tagValue
                        }

                    Write-LabLog -Message "Tagged '$appName' as $targetTag (appId: $appId)" -Level Success
                    $result.taggedApps += @{
                        name   = $appName
                        appId  = $appId
                        tag    = $targetTag
                        status = 'tagged'
                    }
                }
            }
            catch {
                Write-LabLog -Message "Error tagging app '${appName}': $($_.Exception.Message)" -Level Warning
                $result.taggedApps += @{
                    name   = $appName
                    tag    = $targetTag
                    status = 'error'
                }
            }
        }
    }

    # --- 2. Create cloud discovery policies ---
    if ($appGovConfig.PSObject.Properties['discoveryPolicies'] -and $appGovConfig.discoveryPolicies.Count -gt 0) {
        foreach ($policy in $appGovConfig.discoveryPolicies) {
            $policyName = "$prefix-$($policy.name)"

            try {
                if ($PSCmdlet.ShouldProcess($policyName, 'Create cloud discovery policy')) {
                    $existingPolicies = Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint 'policies/' -Method GET

                    $existing = $null
                    if ($existingPolicies -and $existingPolicies.data) {
                        $existing = $existingPolicies.data | Where-Object {
                            $_.name -eq $policyName -and $_.policyType -eq 'DISCOVERY_POLICY'
                        } | Select-Object -First 1
                    }

                    if ($existing) {
                        Write-LabLog -Message "Discovery policy already exists: $policyName" -Level Info
                        $result.discoveryPolicies += @{
                            name   = $policyName
                            id     = $existing._id
                            status = 'existing'
                        }
                        continue
                    }

                    $policyBody = @{
                        name       = $policyName
                        policyType = 'DISCOVERY_POLICY'
                        enabled    = $true
                        filters    = @{}
                    }

                    if ($policy.PSObject.Properties['category'] -and $policy.category) {
                        $policyBody.filters['appCategory'] = @{ eq = @($policy.category) }
                    }

                    if ($policy.PSObject.Properties['thresholdMb'] -and $policy.thresholdMb) {
                        $policyBody.filters['uploadTraffic'] = @{ gt = ($policy.thresholdMb * 1MB) }
                    }

                    $governanceAction = if ($policy.PSObject.Properties['governanceAction'] -and $policy.governanceAction) {
                        $policy.governanceAction
                    } else { 'tag_unsanctioned' }

                    if ($governanceAction -eq 'tag_unsanctioned') {
                        $policyBody['governanceActions'] = @(@{ type = 'tag_unsanctioned' })
                    }

                    $created = Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint 'policies/' -Method POST -Body $policyBody

                    $createdId = if ($created._id) { $created._id } else { 'unknown' }
                    Write-LabLog -Message "Created discovery policy: $policyName (id: $createdId)" -Level Success
                    $result.discoveryPolicies += @{
                        name   = $policyName
                        id     = $createdId
                        status = 'created'
                    }
                }
            }
            catch {
                Write-LabLog -Message "Error creating discovery policy '${policyName}': $($_.Exception.Message)" -Level Warning
            }
        }
    }

    # --- 3. Create session policies ---
    if ($appGovConfig.PSObject.Properties['sessionPolicies'] -and $appGovConfig.sessionPolicies.Count -gt 0) {
        foreach ($policy in $appGovConfig.sessionPolicies) {
            $policyName = "$prefix-$($policy.name)"

            try {
                if ($PSCmdlet.ShouldProcess($policyName, 'Create session policy')) {
                    $existingPolicies = Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint 'policies/' -Method GET

                    $existing = $null
                    if ($existingPolicies -and $existingPolicies.data) {
                        $existing = $existingPolicies.data | Where-Object {
                            $_.name -eq $policyName -and $_.policyType -eq 'SESSION_POLICY'
                        } | Select-Object -First 1
                    }

                    if ($existing) {
                        Write-LabLog -Message "Session policy already exists: $policyName" -Level Info
                        $result.sessionPolicies += @{
                            name   = $policyName
                            id     = $existing._id
                            status = 'existing'
                        }
                        continue
                    }

                    $controlType = if ($policy.PSObject.Properties['controlType'] -and $policy.controlType) {
                        $policy.controlType
                    } else { 'monitor' }

                    $sessionControlType = switch ($controlType) {
                        'monitor'       { 'MONITOR_ONLY' }
                        'blockUpload'   { 'BLOCK_UPLOAD' }
                        'blockDownload' { 'BLOCK_DOWNLOAD' }
                        default         { 'MONITOR_ONLY' }
                    }

                    $policyBody = @{
                        name               = $policyName
                        policyType         = 'SESSION_POLICY'
                        enabled            = $true
                        sessionControlType = $sessionControlType
                        filters            = @{
                            activity = @{ eq = @('upload') }
                        }
                    }

                    $contentInspection = $false
                    if ($policy.PSObject.Properties['contentInspection'] -and $policy.contentInspection) {
                        $contentInspection = [bool]$policy.contentInspection
                    }
                    if ($contentInspection) {
                        $policyBody['contentInspection'] = @{ enabled = $true }
                    }

                    $created = Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint 'policies/' -Method POST -Body $policyBody

                    $createdId = if ($created._id) { $created._id } else { 'unknown' }
                    Write-LabLog -Message "Created session policy: $policyName (id: $createdId)" -Level Success
                    $result.sessionPolicies += @{
                        name               = $policyName
                        id                 = $createdId
                        controlType        = $controlType
                        contentInspection  = $contentInspection
                        status             = 'created'
                    }
                }
            }
            catch {
                Write-LabLog -Message "Error creating session policy '${policyName}': $($_.Exception.Message). Ensure Conditional Access App Control is enabled." -Level Warning
            }
        }
    }

    # --- 4. Log manual steps ---
    Write-ManualSteps -Config $Config -Result $result

    return $result
}

function Write-ManualSteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [hashtable]$Result
    )

    $appGovConfig = $Config.workloads.appGovernance
    if ($appGovConfig.PSObject.Properties['manualSteps'] -and $appGovConfig.manualSteps.Count -gt 0) {
        Write-LabLog -Message '--- Manual configuration required (no API available) ---' -Level Warning
        foreach ($step in $appGovConfig.manualSteps) {
            $stepName = if ($step.PSObject.Properties['name']) { $step.name } else { 'Unnamed step' }
            $portal = if ($step.PSObject.Properties['portal']) { $step.portal } else { 'N/A' }
            $instructions = if ($step.PSObject.Properties['instructions']) { $step.instructions } else { '' }

            Write-LabLog -Message "MANUAL: $stepName — Portal: $portal" -Level Warning
            if ($instructions) {
                Write-LabLog -Message "  Instructions: $instructions" -Level Info
            }

            $Result.manualSteps += @{
                name         = $stepName
                portal       = $portal
                instructions = $instructions
                status       = 'manual'
            }
        }
    }
}

function Remove-AppGovernance {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    $appGovConfig = $Config.workloads.appGovernance
    $prefix = $Config.prefix

    $cloud = if ($Config.PSObject.Properties['cloud'] -and -not [string]::IsNullOrWhiteSpace([string]$Config.cloud)) {
        [string]$Config.cloud
    } else { 'commercial' }

    $portalUrl = Get-MdcaPortalUrl -Cloud $cloud -Config $Config

    $mdcaToken = $null
    if (-not $WhatIfPreference) {
        try {
            $tenantId = if ($env:PURVIEW_TENANT_ID) { $env:PURVIEW_TENANT_ID }
                        elseif ($Config.PSObject.Properties['tenantId']) { [string]$Config.tenantId }
                        else { (Get-MgContext).TenantId }

            $mdcaToken = Connect-LabMdca -PortalUrl $portalUrl -TenantId $tenantId
        }
        catch {
            Write-LabLog -Message "MDCA API authentication failed during removal: $($_.Exception.Message). Skipping App Governance removal." -Level Warning
            return
        }
    }

    # --- 1. Remove discovery policies ---
    $targetDiscoveryPolicies = @()

    if ($Manifest -and $Manifest.PSObject.Properties['discoveryPolicies']) {
        foreach ($mp in @($Manifest.discoveryPolicies)) {
            if ($mp.id -and $mp.id -ne 'unknown') {
                $targetDiscoveryPolicies += @{ name = [string]$mp.name; id = [string]$mp.id }
            }
            elseif ($mp.name) {
                $targetDiscoveryPolicies += @{ name = [string]$mp.name; id = $null }
            }
        }
    }

    if ($targetDiscoveryPolicies.Count -eq 0 -and $appGovConfig.PSObject.Properties['discoveryPolicies']) {
        foreach ($policy in $appGovConfig.discoveryPolicies) {
            $targetDiscoveryPolicies += @{ name = "$prefix-$($policy.name)"; id = $null }
        }
    }

    foreach ($target in $targetDiscoveryPolicies) {
        $name = $target.name
        try {
            if ($PSCmdlet.ShouldProcess($name, 'Remove cloud discovery policy')) {
                if ($target.id) {
                    Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint "policies/$($target.id)/" -Method DELETE
                    Write-LabLog -Message "Removed discovery policy: $name" -Level Success
                }
                else {
                    $allPolicies = Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint 'policies/' -Method GET

                    $match = $null
                    if ($allPolicies -and $allPolicies.data) {
                        $match = $allPolicies.data | Where-Object {
                            $_.name -eq $name -and $_.policyType -eq 'DISCOVERY_POLICY'
                        } | Select-Object -First 1
                    }

                    if ($match) {
                        Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                            -Endpoint "policies/$($match._id)/" -Method DELETE
                        Write-LabLog -Message "Removed discovery policy: $name" -Level Success
                    }
                    else {
                        Write-LabLog -Message "Discovery policy not found, skipping: $name" -Level Warning
                    }
                }
            }
        }
        catch {
            Write-LabLog -Message "Error removing discovery policy '${name}': $($_.Exception.Message)" -Level Warning
        }
    }

    # --- 2. Remove session policies ---
    $targetSessionPolicies = @()

    if ($Manifest -and $Manifest.PSObject.Properties['sessionPolicies']) {
        foreach ($mp in @($Manifest.sessionPolicies)) {
            if ($mp.id -and $mp.id -ne 'unknown') {
                $targetSessionPolicies += @{ name = [string]$mp.name; id = [string]$mp.id }
            }
            elseif ($mp.name) {
                $targetSessionPolicies += @{ name = [string]$mp.name; id = $null }
            }
        }
    }

    if ($targetSessionPolicies.Count -eq 0 -and $appGovConfig.PSObject.Properties['sessionPolicies']) {
        foreach ($policy in $appGovConfig.sessionPolicies) {
            $targetSessionPolicies += @{ name = "$prefix-$($policy.name)"; id = $null }
        }
    }

    foreach ($target in $targetSessionPolicies) {
        $name = $target.name
        try {
            if ($PSCmdlet.ShouldProcess($name, 'Remove session policy')) {
                if ($target.id) {
                    Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint "policies/$($target.id)/" -Method DELETE
                    Write-LabLog -Message "Removed session policy: $name" -Level Success
                }
                else {
                    $allPolicies = Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint 'policies/' -Method GET

                    $match = $null
                    if ($allPolicies -and $allPolicies.data) {
                        $match = $allPolicies.data | Where-Object {
                            $_.name -eq $name -and $_.policyType -eq 'SESSION_POLICY'
                        } | Select-Object -First 1
                    }

                    if ($match) {
                        Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                            -Endpoint "policies/$($match._id)/" -Method DELETE
                        Write-LabLog -Message "Removed session policy: $name" -Level Success
                    }
                    else {
                        Write-LabLog -Message "Session policy not found, skipping: $name" -Level Warning
                    }
                }
            }
        }
        catch {
            Write-LabLog -Message "Error removing session policy '${name}': $($_.Exception.Message)" -Level Warning
        }
    }

    # --- 3. Untag AI apps (restore to monitored) ---
    $targetApps = @()

    if ($Manifest -and $Manifest.PSObject.Properties['taggedApps']) {
        $targetApps = @($Manifest.taggedApps | Where-Object { $_.status -eq 'tagged' -and $_.appId })
    }
    elseif ($appGovConfig.PSObject.Properties['aiApps']) {
        $targetApps = @($appGovConfig.aiApps | ForEach-Object { @{ name = $_.name; appId = $null } })
    }

    foreach ($app in $targetApps) {
        $appName = $app.name
        try {
            if ($PSCmdlet.ShouldProcess($appName, 'Restore app tag to monitored')) {
                if ($app.appId) {
                    Invoke-MdcaApi -PortalUrl $portalUrl -Token $mdcaToken `
                        -Endpoint "discovery/discovered_apps/tag/" -Method POST `
                        -Body @{
                            appIds = @($app.appId)
                            tag    = 2
                        }
                    Write-LabLog -Message "Restored '$appName' to monitored (appId: $($app.appId))" -Level Success
                }
                else {
                    Write-LabLog -Message "No appId for '$appName', skipping untag. Tag may need manual reset." -Level Warning
                }
            }
        }
        catch {
            Write-LabLog -Message "Error untagging app '${appName}': $($_.Exception.Message)" -Level Warning
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-AppGovernance'
    'Remove-AppGovernance'
)
