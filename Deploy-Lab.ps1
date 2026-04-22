#Requires -Version 7.0

<#
.SYNOPSIS
    Main deployment orchestrator for purview-lab-deployer.

.DESCRIPTION
    Deploys Microsoft Purview lab workloads in dependency order based on a
    JSON configuration file. Produces a manifest of all created resources
    for later teardown.

.PARAMETER ConfigPath
    Path to the lab configuration JSON file. Optional when -LabProfile is used.

.PARAMETER LabProfile
    Deployment profile name. Resolves to a config file under configs/<cloud>/.
    Available profiles: basic, ai, purview-sentinel.
    Deprecated aliases: basic-lab, shadow-ai, copilot-dlp, copilot-protection, ai-security.

.PARAMETER SkipAuth
    Skip connecting to Exchange Online and Microsoft Graph (for testing).

.PARAMETER TenantId
    Microsoft Entra tenant ID. Defaults to environment variable PURVIEW_TENANT_ID.
    Required unless -SkipAuth is specified.

.PARAMETER Cloud
    Cloud profile to use (`commercial` or `gcc`). If omitted, uses config value.

.PARAMETER SkipTestUsers
    Skip the test users workload entirely. Useful when deploying policies against
    existing tenant users without touching the user/group workload.

.PARAMETER TestUsers
    Override the test users defined in the config with your own list of existing
    tenant UPNs. When supplied, the config's testUsers.users array is replaced
    with these UPNs and the mode is forced to 'existing'. Groups defined in the
    config are cleared (they reference the config's user aliases which won't map).
    When omitted, the users already listed in the config are used as-is.

.EXAMPLE
    ./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic

.EXAMPLE
    ./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai

.EXAMPLE
    ./Deploy-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel

.EXAMPLE
    ./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic -TestUsers alice@contoso.com,bob@contoso.com

.EXAMPLE
    ./Deploy-Lab.ps1 -ConfigPath configs/commercial/basic-demo.json -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [Parameter()]
    [ValidateSet('basic', 'ai', 'purview-sentinel', 'basic-lab', 'shadow-ai', 'copilot-dlp', 'copilot-protection', 'ai-security')]
    [string]$LabProfile,

    [Parameter()]
    [switch]$SkipAuth,

    [Parameter()]
    [string]$TenantId = $env:PURVIEW_TENANT_ID,

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = $env:PURVIEW_CLOUD,

    [Parameter()]
    [string[]]$TestUsers,

    [Parameter()]
    [switch]$SkipTestUsers,

    [Parameter()]
    [string]$SubscriptionId = $env:PURVIEW_SUBSCRIPTION_ID
)

$ErrorActionPreference = 'Stop'

# Import Prerequisites early for profile resolution
Import-Module (Join-Path $PSScriptRoot 'modules' 'Prerequisites.psm1') -Force

# Profile-to-config resolution
$profileConfigMap = Get-ProfileConfigMapping

if (-not [string]::IsNullOrWhiteSpace($LabProfile) -and -not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    throw 'Specify either -LabProfile or -ConfigPath, not both.'
}

if (-not [string]::IsNullOrWhiteSpace($LabProfile)) {
    $LabProfile = Resolve-LabProfile -LabProfile $LabProfile
    $resolvedCloud = if ([string]::IsNullOrWhiteSpace($Cloud)) { 'commercial' } else { $Cloud }
    $configFileName = $profileConfigMap[$LabProfile]
    $ConfigPath = Join-Path $PSScriptRoot "configs/$resolvedCloud/$configFileName"
    if (-not (Test-Path $ConfigPath -PathType Leaf)) {
        throw "Profile '$LabProfile' config not found for cloud '$resolvedCloud': $ConfigPath"
    }
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    throw 'Either -LabProfile or -ConfigPath is required.'
}

# Import all modules
foreach ($mod in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'modules') -Filter '*.psm1')) {
    Import-Module $mod.FullName -Force
}

try {
    # Initialize logging
    Initialize-LabLogging -Prefix 'PurviewLab'
    Write-LabLog -Message 'Deploy-Lab started.' -Level Info

    # Load configuration
    Write-LabStep -StepName 'Config' -Description 'Loading lab configuration'
    $Config = Import-LabConfig -ConfigPath $ConfigPath
    if (-not (Test-LabConfigValidity -Config $Config)) {
        Write-LabLog -Message 'Configuration has validation warnings. Review above messages.' -Level Warning
    }
    $resolvedCloud = Resolve-LabCloud -Cloud $Cloud -Config $Config
    $capabilityProfile = Import-LabCloudProfile -Cloud $resolvedCloud -RepositoryRoot $PSScriptRoot

    # Apply SkipTestUsers override
    if ($SkipTestUsers -and $Config.workloads.testUsers) {
        if ($Config.workloads.testUsers.PSObject.Properties['enabled']) {
            $Config.workloads.testUsers.enabled = $false
        } else {
            $Config.workloads.testUsers | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $false
        }
        Write-LabLog -Message 'Test user creation skipped (-SkipTestUsers).' -Level Info
    }

    # Apply TestUsers override — replace config's user list with caller-supplied UPNs
    if ($TestUsers -and $TestUsers.Count -gt 0 -and $Config.workloads.testUsers) {
        $upnObjects = @($TestUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            [PSCustomObject]@{ upn = $_.Trim() }
        })

        if ($Config.workloads.testUsers.PSObject.Properties['users']) {
            $Config.workloads.testUsers.users = $upnObjects
        } else {
            $Config.workloads.testUsers | Add-Member -NotePropertyName 'users' -NotePropertyValue $upnObjects
        }

        # Caller-supplied UPNs can't map to the config's group member aliases, so drop groups
        if ($Config.workloads.testUsers.PSObject.Properties['groups']) {
            $Config.workloads.testUsers.groups = @()
        }

        # Force existing mode — arbitrary UPNs can't be auto-created
        if ($Config.workloads.testUsers.PSObject.Properties['mode']) {
            $Config.workloads.testUsers.mode = 'existing'
        } else {
            $Config.workloads.testUsers | Add-Member -NotePropertyName 'mode' -NotePropertyValue 'existing'
        }

        Write-LabLog -Message "TestUsers overridden by caller: $($upnObjects.Count) UPN(s). Groups cleared; mode forced to 'existing'." -Level Info
    }

    # Sentinel integration: allow -SubscriptionId / PURVIEW_SUBSCRIPTION_ID env var to
    # override the config value. The config ships with an empty subscriptionId so
    # that repo clones don't carry a hardcoded tenant-specific GUID.
    if ($Config.workloads.sentinelIntegration -and
        $Config.workloads.sentinelIntegration.PSObject.Properties['enabled'] -and
        [bool]$Config.workloads.sentinelIntegration.enabled) {

        if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
            if ($Config.workloads.sentinelIntegration.PSObject.Properties['subscriptionId']) {
                $Config.workloads.sentinelIntegration.subscriptionId = $SubscriptionId
            }
            else {
                $Config.workloads.sentinelIntegration |
                    Add-Member -NotePropertyName 'subscriptionId' -NotePropertyValue $SubscriptionId
            }
            Write-LabLog -Message "Sentinel subscription ID provided via -SubscriptionId / PURVIEW_SUBSCRIPTION_ID." -Level Info
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$Config.workloads.sentinelIntegration.subscriptionId)) {
            throw 'sentinelIntegration workload is enabled but no subscription ID was provided. Pass -SubscriptionId, set PURVIEW_SUBSCRIPTION_ID, or populate workloads.sentinelIntegration.subscriptionId in the config.'
        }
    }

    Write-LabLog -Message "Lab: $($Config.labName) | Prefix: $($Config.prefix) | Domain: $($Config.domain) | Cloud: $resolvedCloud" -Level Info

    # Validate workload compatibility for selected cloud
    $compatibility = Test-LabWorkloadCompatibility -Config $Config -CapabilityProfile $capabilityProfile -Operation Deploy
    foreach ($warning in $compatibility.warnings) {
        Write-LabLog -Message $warning -Level Warning
    }
    if ($compatibility.blockers.Count -gt 0) {
        foreach ($blocker in $compatibility.blockers) {
            Write-LabLog -Message $blocker -Level Error
        }
        throw "Configuration contains workloads unavailable for cloud '$resolvedCloud'."
    }

    # Test prerequisites
    Write-LabStep -StepName 'Prerequisites' -Description 'Validating prerequisites'
    if (-not (Test-LabPrerequisites)) {
        Write-LabLog -Message 'Prerequisites check failed. Exiting.' -Level Error
        exit 1
    }
    Write-LabLog -Message 'All prerequisites satisfied.' -Level Success

    # Connect to services
    if (-not $SkipAuth) {
        if ([string]::IsNullOrWhiteSpace($TenantId)) {
            throw 'TenantId is required when authentication is enabled. Use -TenantId or set PURVIEW_TENANT_ID.'
        }

        Write-LabStep -StepName 'Auth' -Description 'Connecting to cloud services'
        Connect-LabServices -TenantId $TenantId
        Write-LabLog -Message 'Connected to Exchange Online and Microsoft Graph.' -Level Success

        $resolvedDomain = Resolve-LabTenantDomain -ConfiguredDomain $Config.domain
        if (-not [string]::Equals($resolvedDomain, [string]$Config.domain, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-LabLog -Message "Configured domain '$($Config.domain)' is not verified in this tenant. Using '$resolvedDomain'." -Level Warning
            $Config.domain = $resolvedDomain
        }
    }
    else {
        Write-LabLog -Message 'Skipping authentication (-SkipAuth).' -Level Warning
    }

    # Utility functions (Get-LabStringArray, Get-LabSupportedParameterName,
    # Get-LabObjectProperty, Get-LabDlpConfiguredLabels) are now in Prerequisites.psm1

    if (-not $SkipAuth -and $Config.workloads.dlp.enabled) {
        Write-LabStep -StepName 'DLPPreflight' -Description 'Validating DLP enforcement configuration'

        $dlpPreflightBlockers = [System.Collections.Generic.List[string]]::new()
        $dlpPreflightWarnings = [System.Collections.Generic.List[string]]::new()
        $newPolicyCommand = Get-Command -Name New-DlpCompliancePolicy -ErrorAction SilentlyContinue
        $setPolicyCommand = Get-Command -Name Set-DlpCompliancePolicy -ErrorAction SilentlyContinue
        $newRuleCommand = Get-Command -Name New-DlpComplianceRule -ErrorAction SilentlyContinue
        $setRuleCommand = Get-Command -Name Set-DlpComplianceRule -ErrorAction SilentlyContinue
        $policyCommands = @($newPolicyCommand, $setPolicyCommand) | Where-Object { $_ }
        $ruleCommands = @($newRuleCommand, $setRuleCommand) | Where-Object { $_ }

        if ($policyCommands.Count -eq 0) {
            $dlpPreflightBlockers.Add('New/Set-DlpCompliancePolicy cmdlets are unavailable.')
        }
        if ($ruleCommands.Count -eq 0) {
            $dlpPreflightBlockers.Add('New/Set-DlpComplianceRule cmdlets are unavailable.')
        }

        if ($policyCommands.Count -eq 0 -or $ruleCommands.Count -eq 0) {
            # Skip per-policy/rule preflight when cmdlets are unavailable
        }
        else {
        foreach ($policy in @($Config.workloads.dlp.policies)) {
            $policyName = "$($Config.prefix)-$($policy.name)"

            $appliesToGroups = Get-LabStringArray -Value $policy.appliesToGroups
            if ($appliesToGroups.Count -gt 0) {
                $scopeSupport = Get-LabSupportedParameterName -Commands $policyCommands -CandidateNames @('ExchangeSenderMemberOf', 'ExchangeSenderMemberOfGroups', 'UserScope')
                if (-not $scopeSupport) {
                    $dlpPreflightWarnings.Add("Policy '$policyName' uses appliesToGroups, but no supported policy scope parameter exists on Set/New-DlpCompliancePolicy. Group scoping will be ignored.")
                }
            }

            $excludeGroups = Get-LabStringArray -Value $policy.excludeGroups
            if ($excludeGroups.Count -gt 0) {
                $excludeSupport = Get-LabSupportedParameterName -Commands $policyCommands -CandidateNames @('ExceptIfUserMemberOf', 'ExchangeSenderMemberOfException', 'ExcludedUsers')
                if (-not $excludeSupport) {
                    $dlpPreflightWarnings.Add("Policy '$policyName' uses excludeGroups, but no supported exclusion parameter exists. Exclusions will be ignored.")
                }
            }

            foreach ($rule in @($policy.rules)) {
                $ruleName = "$($Config.prefix)-$($rule.name)"
                $configuredLabels = Get-LabDlpConfiguredLabels -Policy $policy -Rule $rule
                if ($configuredLabels.Count -gt 0) {
                    $labelSupport = Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('SensitivityLabels', 'SensitivityLabel', 'Labels')
                    if (-not $labelSupport) {
                        $dlpPreflightWarnings.Add("Rule '$ruleName' uses label conditions, but Set/New-DlpComplianceRule has no supported label parameter. Label conditions will be ignored.")
                    }
                }

                $enforcement = if (($rule.PSObject.Properties.Name -contains 'enforcement') -and $null -ne $rule.enforcement) { $rule.enforcement } else { $null }
                if (-not $enforcement) {
                    continue
                }

                $action = if (($enforcement.PSObject.Properties.Name -contains 'action') -and -not [string]::IsNullOrWhiteSpace([string]$enforcement.action)) {
                    ([string]$enforcement.action).Trim()
                }
                else {
                    $null
                }

                if ($action) {
                    $actionSupport = Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('BlockAccess', 'Mode', 'EnforcementMode', 'Action')
                    if (-not $actionSupport) {
                        $dlpPreflightWarnings.Add("Rule '$ruleName' requests enforcement action '$action', but no supported action parameter exists on Set/New-DlpComplianceRule. Baseline rule creation will continue.")
                    }

                    if ($action -eq 'allowWithJustification') {
                        $overrideSupport = Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('AllowOverrideWithJustification', 'AllowOverride', 'UserCanOverride')
                        if (-not $overrideSupport) {
                            $dlpPreflightWarnings.Add("Rule '$ruleName' requests allowWithJustification, but no override parameter exists on Set/New-DlpComplianceRule. Rule will fall back to audit behavior.")
                        }
                    }
                }

                # User notifications default to enabled when enforcement exists
                $notifySupport = Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('NotifyUser', 'UserNotificationEnabled')
                if (-not $notifySupport) {
                    $dlpPreflightWarnings.Add("Rule '$ruleName' has enforcement configured, but no supported notify parameter exists.")
                }
                $policyTipSupport = Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('NotifyPolicyTipCustomText', 'PolicyTipCustomText')
                if (-not $policyTipSupport) {
                    $dlpPreflightWarnings.Add("Rule '$ruleName' has enforcement configured, but no supported policy tip parameter exists.")
                }

                if (($enforcement.PSObject.Properties.Name -contains 'alert') -and $null -ne $enforcement.alert -and [bool]$enforcement.alert.enabled) {
                    $alertSupport = Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('GenerateAlert', 'AlertEnabled')
                    if (-not $alertSupport) {
                        $dlpPreflightWarnings.Add("Rule '$ruleName' requests alerts, but no supported alert parameter exists.")
                    }
                }

                if (($enforcement.PSObject.Properties.Name -contains 'incidentReport') -and $null -ne $enforcement.incidentReport -and [bool]$enforcement.incidentReport.enabled) {
                    $incidentSupport = Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('IncidentReportEnabled', 'GenerateIncidentReport')
                    if (-not $incidentSupport) {
                        $dlpPreflightWarnings.Add("Rule '$ruleName' requests incident reports, but no supported incident-report parameter exists.")
                    }
                }
            }
        }
        } # end else (cmdlets available)

        foreach ($warning in @($dlpPreflightWarnings | Sort-Object -Unique)) {
            Write-LabLog -Message $warning -Level Warning
        }

        if ($dlpPreflightBlockers.Count -gt 0) {
            $blockerSummary = (@($dlpPreflightBlockers | Sort-Object -Unique) -join '; ')
            throw "DLP enforcement preflight failed: $blockerSummary"
        }

        Write-LabLog -Message 'DLP enforcement preflight passed.' -Level Success
    }

    # Copilot-specific preflight: warn if demo users don't have Microsoft 365 Copilot licenses.
    # A missing license is the #1 silent demo failure — DLP policies deploy fine but the user
    # hits "Copilot not available" before DLP has a chance to enforce anything.
    if (-not $SkipAuth -and $Config.workloads.dlp.enabled) {
        $copilotPolicyPresent = @($Config.workloads.dlp.policies |
                Where-Object { @($_.locations) -contains 'CopilotExperiences' }).Count -gt 0

        if ($copilotPolicyPresent -and $Config.workloads.testUsers.users) {
            Write-LabStep -StepName 'CopilotLicense' -Description 'Verifying demo users have Microsoft 365 Copilot licenses'

            $copilotSkuId = '639dec6b-bb19-468b-871c-c5c441c4b0cb'
            $unlicensed = [System.Collections.Generic.List[string]]::new()
            $checkFailed = $false

            foreach ($user in @($Config.workloads.testUsers.users)) {
                $upn = [string]$user.upn
                if ([string]::IsNullOrWhiteSpace($upn)) { continue }

                try {
                    $licenses = Get-MgUserLicenseDetail -UserId $upn -ErrorAction Stop
                    if (-not ($licenses | Where-Object { $_.SkuId -eq $copilotSkuId })) {
                        $unlicensed.Add($upn)
                    }
                }
                catch {
                    $checkFailed = $true
                    Write-LabLog -Message "Could not check Copilot license for '$upn': $($_.Exception.Message)" -Level Warning
                }
            }

            if ($unlicensed.Count -gt 0) {
                Write-LabLog -Message "Microsoft 365 Copilot SKU not assigned to: $($unlicensed -join ', '). DLP policies will deploy, but Copilot will not respond for these users until a license is assigned." -Level Warning
            }
            elseif (-not $checkFailed) {
                Write-LabLog -Message 'All demo users have Microsoft 365 Copilot licenses.' -Level Success
            }
        }
    }

    # Initialize manifest
    $manifest = @{}
    $failedWorkloads = @()
    $deployedWorkloads = @()

    # Helper: deploy a workload with error isolation
    function Invoke-Workload {
        param([string]$Name, [string]$Step, [string]$Description, [scriptblock]$Action)
        Write-LabStep -StepName $Step -Description $Description
        try {
            $result = & $Action
            if ($result) { $manifest[$Name] = $result }
            $script:deployedWorkloads += $Name
            Write-LabLog -Message "$Step deployment complete." -Level Success
        }
        catch {
            Write-LabLog -Message "$Step FAILED: $_" -Level Error
            $script:failedWorkloads += $Name
        }
    }

    function Test-DeployedEntityExists {
        param(
            [Parameter(Mandatory)]
            [string]$EntityType,

            [Parameter(Mandatory)]
            [string]$EntityName,

            [Parameter(Mandatory)]
            [scriptblock]$CheckAction
        )

        $maxAttempts = 6

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                if (& $CheckAction $EntityName) {
                    return $true
                }
            }
            catch {
                # Known Microsoft-side visibility lag: newly created policies
                # (especially AI-Applications retention) may take 10-30+ min to
                # appear in Get-*ComplianceP olicy results even though the PUT
                # succeeded. Treat ManagementObjectNotFoundException as soft
                # (warn on final attempt) so the deploy completes and the
                # manifest is still written. Operator can verify via portal.
                if ($attempt -eq $maxAttempts) {
                    if ($_.Exception.Message -match 'ManagementObjectNotFoundException|FfoConfigurationSession') {
                        Write-LabLog -Message "Validation check for $EntityType '$EntityName' exhausted retries — Microsoft backend query-cache propagation lag. Policy likely exists; verify via portal. Continuing." -Level Warning
                        return $false
                    }
                    throw "Validation check failed for $EntityType '$EntityName': $($_.Exception.Message)"
                }

                Write-LabLog -Message "Validation check error for $EntityType '$EntityName' (attempt $attempt/$maxAttempts): $($_.Exception.Message)" -Level Warning
            }

            if ($attempt -lt $maxAttempts) {
                Start-Sleep -Seconds 5
            }
        }

        return $false
    }

    # Deploy workloads in dependency order
    if ($Config.workloads.testUsers.enabled) {
        Invoke-Workload -Name 'testUsers' -Step 'TestUsers' -Description 'Deploying test users' -Action {
            Deploy-TestUsers -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'testUsers workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.sensitivityLabels.enabled) {
        Invoke-Workload -Name 'sensitivityLabels' -Step 'SensitivityLabels' -Description 'Deploying sensitivity labels' -Action {
            Deploy-SensitivityLabels -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'sensitivityLabels workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.dlp.enabled) {
        Invoke-Workload -Name 'dlp' -Step 'DLP' -Description 'Deploying DLP policies' -Action {
            Deploy-DLP -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'dlp workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.retention.enabled) {
        Invoke-Workload -Name 'retention' -Step 'Retention' -Description 'Deploying retention policies' -Action {
            Deploy-Retention -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'retention workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.eDiscovery.enabled) {
        Invoke-Workload -Name 'eDiscovery' -Step 'EDiscovery' -Description 'Deploying eDiscovery cases' -Action {
            Deploy-EDiscovery -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'eDiscovery workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.communicationCompliance.enabled) {
        Invoke-Workload -Name 'communicationCompliance' -Step 'CommunicationCompliance' -Description 'Deploying communication compliance policies' -Action {
            Deploy-CommunicationCompliance -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'communicationCompliance workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.insiderRisk.enabled) {
        Invoke-Workload -Name 'insiderRisk' -Step 'InsiderRisk' -Description 'Deploying insider risk management policies' -Action {
            Deploy-InsiderRisk -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'insiderRisk workload is disabled, skipping.' -Level Info }

    if ($Config.workloads.PSObject.Properties['conditionalAccess'] -and $Config.workloads.conditionalAccess.enabled) {
        Invoke-Workload -Name 'conditionalAccess' -Step 'ConditionalAccess' -Description 'Deploying Conditional Access policies' -Action {
            Deploy-ConditionalAccess -Config $Config -WhatIf:$WhatIfPreference
        }
    }

    if ($Config.workloads.PSObject.Properties['auditConfig'] -and $Config.workloads.auditConfig.enabled) {
        Invoke-Workload -Name 'auditConfig' -Step 'AuditConfig' -Description 'Configuring audit logging for AI activities' -Action {
            Deploy-AuditConfig -Config $Config -WhatIf:$WhatIfPreference
        }
    }

    if ($Config.workloads.PSObject.Properties['sentinelIntegration'] -and $Config.workloads.sentinelIntegration.enabled) {
        if (-not $SkipAuth) {
            Write-LabStep -StepName 'SentinelPrereqs' -Description 'Validating Azure CLI prerequisites for Sentinel'
            if (-not (Test-LabAzPrerequisites -Config $Config)) {
                throw 'Azure prerequisites for sentinelIntegration are not satisfied. See warnings above. (Run az login, az account set, or az provider register as needed.)'
            }
        }
        else {
            Write-LabLog -Message 'Skipping Azure prerequisite checks for sentinelIntegration (-SkipAuth).' -Level Warning
        }
        Invoke-Workload -Name 'sentinelIntegration' -Step 'SentinelIntegration' -Description 'Provisioning Sentinel workspace + Purview data connectors' -Action {
            Deploy-SentinelIntegration -Config $Config -WhatIf:$WhatIfPreference
        }
    }

    if ($Config.workloads.testData.enabled) {
        Invoke-Workload -Name 'testData' -Step 'TestData' -Description 'Sending test data (emails, files)' -Action {
            Send-TestData -Config $Config -WhatIf:$WhatIfPreference
        }
    } else { Write-LabLog -Message 'testData workload is disabled, skipping.' -Level Info }

    # Export manifest (skip in WhatIf)
    $manifestPath = $null
    if (-not $WhatIfPreference) {
        $manifestDir = Join-Path (Join-Path $PSScriptRoot 'manifests') $resolvedCloud
        if (-not (Test-Path $manifestDir)) {
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        }
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $manifestPath = Join-Path $manifestDir "$($Config.prefix)_${timestamp}.json"
        Export-LabManifest -ManifestData ([PSCustomObject]$manifest) -OutputPath $manifestPath
        Write-LabLog -Message "Manifest exported to $manifestPath" -Level Success
    }
    else {
        Write-LabLog -Message 'WhatIf mode is active. Skipping manifest export.' -Level Info
    }

    if (-not $WhatIfPreference -and -not $SkipAuth) {
        Write-LabStep -StepName 'Validation' -Description 'Validating deployed objects'
        $validationFailures = [System.Collections.Generic.List[string]]::new()
        $validationWarnings = [System.Collections.Generic.List[string]]::new()

        if ($manifest.ContainsKey('testUsers') -and $manifest.testUsers -and $manifest.testUsers.groups) {
            foreach ($groupName in @($manifest.testUsers.groups)) {
                $targetGroupName = [string]$groupName
                if ([string]::IsNullOrWhiteSpace($targetGroupName)) {
                    continue
                }

                $groupExists = Test-DeployedEntityExists -EntityType 'Group' -EntityName $targetGroupName -CheckAction {
                    param($name)
                    $escapedName = $name.Replace("'", "''")
                    $group = Get-MgGroup -Filter "displayName eq '$escapedName'" -ErrorAction Stop | Select-Object -First 1
                    return [bool]$group
                }

                if (-not $groupExists) {
                    $validationFailures.Add("Group '$targetGroupName'")
                }
            }
        }

        if ($manifest.ContainsKey('dlp') -and $manifest.dlp -and $manifest.dlp.policies) {
            foreach ($policyName in @($manifest.dlp.policies)) {
                $targetPolicyName = [string]$policyName
                if ([string]::IsNullOrWhiteSpace($targetPolicyName)) {
                    continue
                }

                $policyExists = Test-DeployedEntityExists -EntityType 'DLP policy' -EntityName $targetPolicyName -CheckAction {
                    param($name)
                    $policy = Get-DlpCompliancePolicy -Identity $name -ErrorAction Stop
                    return [bool]$policy
                }

                if (-not $policyExists) {
                    $validationFailures.Add("DLP policy '$targetPolicyName'")
                }
            }
        }

        if ($Config.workloads.dlp.enabled -and $Config.workloads.dlp.policies) {
            foreach ($policy in @($Config.workloads.dlp.policies)) {
                $targetPolicyName = "$($Config.prefix)-$($policy.name)"
                # Copilot (M365Copilot) location rules only honor AdvancedRule + RestrictAccess.
                # BlockAccess / NotifyUser / GenerateAlert / GenerateIncidentReport are rejected
                # by the engine. Skip those validation checks for Copilot rules.
                $isCopilotPolicy = ($policy.PSObject.Properties.Name -contains 'locations') -and (@($policy.locations) -contains 'CopilotExperiences')
                foreach ($rule in @($policy.rules)) {
                    $targetRuleName = "$($Config.prefix)-$($rule.name)"

                    $ruleExists = Test-DeployedEntityExists -EntityType 'DLP rule' -EntityName $targetRuleName -CheckAction {
                        param($name)
                        $ruleObject = Get-DlpComplianceRule -Identity $name -ErrorAction Stop
                        return [bool]$ruleObject
                    }

                    if (-not $ruleExists) {
                        $validationWarnings.Add("DLP rule '$targetRuleName' could not be validated (may be access denied or transient)")
                        continue
                    }

                    $ruleObject = Get-DlpComplianceRule -Identity $targetRuleName -ErrorAction Stop
                    $configuredLabels = Get-LabDlpConfiguredLabels -Policy $policy -Rule $rule
                    if ($configuredLabels.Count -gt 0) {
                        $labelsProp = Get-LabObjectProperty -Object $ruleObject -CandidateNames @('SensitivityLabels', 'SensitivityLabel', 'Labels')
                        if ($labelsProp.found) {
                            $actualLabels = Get-LabStringArray -Value $labelsProp.value
                            foreach ($expectedLabel in $configuredLabels) {
                                if ($expectedLabel -notin $actualLabels) {
                                    $validationFailures.Add("DLP rule '$targetRuleName' missing expected label condition '$expectedLabel'")
                                }
                            }
                        }
                        elseif (-not $isCopilotPolicy) {
                            $validationWarnings.Add("DLP rule '$targetRuleName' configured labels could not be validated because no label property was returned by Get-DlpComplianceRule.")
                        }
                    }

                    $enforcement = if (($rule.PSObject.Properties.Name -contains 'enforcement') -and $null -ne $rule.enforcement) { $rule.enforcement } else { $null }
                    if (-not $enforcement) {
                        continue
                    }

                    # Copilot rules don't accept BlockAccess/NotifyUser/GenerateAlert/IncidentReport
                    # — skip those validation checks. The RestrictAccess action is the enforcement
                    # and is set via the AdvancedRule path.
                    if ($isCopilotPolicy) {
                        continue
                    }

                    # Re-check cmdlet capability so validation matches what deploy could actually set
                    $ruleCommands = @('New-DlpComplianceRule', 'Set-DlpComplianceRule') | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Where-Object { $_ }
                    $actionParamSupported = [bool](Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('BlockAccess', 'Mode', 'EnforcementMode', 'Action'))
                    $overrideParamSupported = [bool](Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('AllowOverrideWithJustification', 'AllowOverride', 'UserCanOverride'))
                    $notifyParamSupported = [bool](Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('NotifyUser', 'UserNotificationEnabled'))
                    $alertParamSupported = [bool](Get-LabSupportedParameterName -Commands $ruleCommands -CandidateNames @('GenerateAlert', 'AlertEnabled'))

                    $action = if (($enforcement.PSObject.Properties.Name -contains 'action') -and -not [string]::IsNullOrWhiteSpace([string]$enforcement.action)) {
                        ([string]$enforcement.action).Trim()
                    }
                    else {
                        $null
                    }

                    if ($action -and $actionParamSupported) {
                        $blockProp = Get-LabObjectProperty -Object $ruleObject -CandidateNames @('BlockAccess')
                        if ($blockProp.found) {
                            $isBlocked = [bool]$blockProp.value
                            if ($action -eq 'block' -and -not $isBlocked) {
                                $validationWarnings.Add("DLP rule '$targetRuleName' expected block action but BlockAccess is not enabled (enforcement may have fallen back to baseline).")
                            }
                            if ($action -eq 'auditOnly' -and $isBlocked) {
                                $validationWarnings.Add("DLP rule '$targetRuleName' expected auditOnly action but BlockAccess is enabled.")
                            }
                        }
                        else {
                            $modeProp = Get-LabObjectProperty -Object $ruleObject -CandidateNames @('Mode', 'EnforcementMode', 'Action')
                            if ($modeProp.found) {
                                $modeValue = [string]$modeProp.value
                                if ($action -eq 'block' -and $modeValue -notmatch 'Enforce|Block') {
                                    $validationWarnings.Add("DLP rule '$targetRuleName' expected block action but $($modeProp.name)='$modeValue' (enforcement may have fallen back to baseline).")
                                }
                                if ($action -eq 'auditOnly' -and $modeValue -match 'Enforce|Block') {
                                    $validationWarnings.Add("DLP rule '$targetRuleName' expected auditOnly action but $($modeProp.name)='$modeValue'.")
                                }
                            }
                            else {
                                $validationWarnings.Add("DLP rule '$targetRuleName' action '$action' could not be validated due to missing BlockAccess/Mode property.")
                            }
                        }
                    }
                    elseif ($action -and -not $actionParamSupported) {
                        $validationWarnings.Add("DLP rule '$targetRuleName' action '$action' skipped validation — cmdlet does not support action parameters in this environment.")
                    }

                    if ($action -eq 'allowWithJustification' -and $overrideParamSupported) {
                        $overrideProp = Get-LabObjectProperty -Object $ruleObject -CandidateNames @('AllowOverrideWithJustification', 'AllowOverride', 'UserCanOverride')
                        if ($overrideProp.found) {
                            if (-not [bool]$overrideProp.value) {
                                $validationWarnings.Add("DLP rule '$targetRuleName' expected user override for justification but '$($overrideProp.name)' is disabled (enforcement may have fallen back).")
                            }
                        }
                        else {
                            $validationWarnings.Add("DLP rule '$targetRuleName' allowWithJustification could not be validated due to missing override property.")
                        }
                    }
                    elseif ($action -eq 'allowWithJustification' -and -not $overrideParamSupported) {
                        $validationWarnings.Add("DLP rule '$targetRuleName' allowWithJustification skipped validation — cmdlet does not support override parameters.")
                    }

                    if (($enforcement.PSObject.Properties.Name -contains 'userNotification') -and $null -ne $enforcement.userNotification -and [bool]$enforcement.userNotification.enabled) {
                        if ($notifyParamSupported) {
                            $notifyProp = Get-LabObjectProperty -Object $ruleObject -CandidateNames @('NotifyUser', 'UserNotificationEnabled')
                            if ($notifyProp.found -and -not [bool]$notifyProp.value) {
                                $validationWarnings.Add("DLP rule '$targetRuleName' expected user notification enabled but '$($notifyProp.name)' is disabled (enforcement may have fallen back).")
                            }
                        }
                        else {
                            $validationWarnings.Add("DLP rule '$targetRuleName' user notification skipped validation — cmdlet does not support notification parameters.")
                        }
                    }

                    if (($enforcement.PSObject.Properties.Name -contains 'alert') -and $null -ne $enforcement.alert -and [bool]$enforcement.alert.enabled) {
                        if ($alertParamSupported) {
                            $alertProp = Get-LabObjectProperty -Object $ruleObject -CandidateNames @('GenerateAlert', 'AlertEnabled')
                            if ($alertProp.found -and -not [bool]$alertProp.value) {
                                $validationWarnings.Add("DLP rule '$targetRuleName' expected alert generation enabled but '$($alertProp.name)' is disabled (enforcement may have fallen back).")
                            }
                        }
                        else {
                            $validationWarnings.Add("DLP rule '$targetRuleName' alert generation skipped validation — cmdlet does not support alert parameters.")
                        }
                    }
                }
            }
        }

        if ($manifest.ContainsKey('retention') -and $manifest.retention -and $manifest.retention.policies) {
            foreach ($manifestPolicy in @($manifest.retention.policies)) {
                $targetPolicyName = $null
                if ($manifestPolicy -is [string]) {
                    $targetPolicyName = [string]$manifestPolicy
                }
                elseif ($manifestPolicy.name) {
                    $targetPolicyName = [string]$manifestPolicy.name
                }

                if ([string]::IsNullOrWhiteSpace($targetPolicyName)) {
                    continue
                }

                $policyExists = Test-DeployedEntityExists -EntityType 'Retention policy' -EntityName $targetPolicyName -CheckAction {
                    param($name)
                    $policy = Get-RetentionCompliancePolicy -Identity $name -ErrorAction Stop
                    return [bool]$policy
                }

                if (-not $policyExists) {
                    # Retention policies — especially AI-Applications scoped
                    # (MicrosoftCopilotExperiences / EnterpriseAIApps / OtherAIApps)
                    # have a Microsoft-side query-cache propagation lag of
                    # 10-30+ min where PUT succeeds but Get-* can't find the
                    # policy yet. Test-DeployedEntityExists's inner retry
                    # tolerance already logged the soft-skip; here we record
                    # as a warning rather than failure so the deploy exits
                    # cleanly. Operator verifies via portal.
                    $validationWarnings.Add("Retention policy '$targetPolicyName' not yet visible to Get-RetentionCompliancePolicy — likely Microsoft-side query-cache lag. Verify via Purview portal; rerun deploy in 15-30 min if needed.")
                }
            }
        }

        if ($manifest.ContainsKey('eDiscovery') -and $manifest.eDiscovery -and $manifest.eDiscovery.cases) {
            foreach ($manifestCase in @($manifest.eDiscovery.cases)) {
                $targetCaseName = [string]$manifestCase.caseName
                if ([string]::IsNullOrWhiteSpace($targetCaseName)) {
                    continue
                }

                $caseExists = Test-DeployedEntityExists -EntityType 'eDiscovery case' -EntityName $targetCaseName -CheckAction {
                    param($name)
                    $filter = "displayName eq '$($name -replace "'","''")'"
                    $response = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/security/cases/ediscoveryCases?`$filter=$filter" -ErrorAction Stop
                    return ($response.value.Count -gt 0)
                }

                if (-not $caseExists) {
                    $validationFailures.Add("eDiscovery case '$targetCaseName'")
                }
            }
        }

        if ($manifest.ContainsKey('communicationCompliance') -and $manifest.communicationCompliance -and $manifest.communicationCompliance.policies) {
            foreach ($manifestPolicy in @($manifest.communicationCompliance.policies)) {
                $targetPolicyName = $null
                if ($manifestPolicy -is [string]) {
                    $targetPolicyName = [string]$manifestPolicy
                }
                elseif ($manifestPolicy.policyName) {
                    $targetPolicyName = [string]$manifestPolicy.policyName
                }
                elseif ($manifestPolicy.name) {
                    $targetPolicyName = [string]$manifestPolicy.name
                }

                if ([string]::IsNullOrWhiteSpace($targetPolicyName)) {
                    continue
                }

                $policyExists = Test-DeployedEntityExists -EntityType 'DSPM for AI policy' -EntityName $targetPolicyName -CheckAction {
                    param($name)
                    $policy = Get-FeatureConfiguration -FeatureScenario KnowYourData -ErrorAction Stop |
                        Where-Object { $_.Name -eq $name } |
                        Select-Object -First 1
                    return [bool]$policy
                }

                if (-not $policyExists) {
                    $validationFailures.Add("DSPM for AI policy '$targetPolicyName'")
                }
            }
        }

        if ($manifest.ContainsKey('insiderRisk') -and $manifest.insiderRisk -and $manifest.insiderRisk.policies) {
            foreach ($manifestPolicy in @($manifest.insiderRisk.policies)) {
                $targetPolicyName = $null
                if ($manifestPolicy -is [string]) {
                    $targetPolicyName = [string]$manifestPolicy
                }
                elseif ($manifestPolicy.name) {
                    $targetPolicyName = [string]$manifestPolicy.name
                }

                if ([string]::IsNullOrWhiteSpace($targetPolicyName)) {
                    continue
                }

                $policyExists = Test-DeployedEntityExists -EntityType 'Insider Risk policy' -EntityName $targetPolicyName -CheckAction {
                    param($name)
                    $policy = Get-InsiderRiskPolicy -ErrorAction Stop |
                        Where-Object { $_.Name -eq $name } |
                        Select-Object -First 1
                    return [bool]$policy
                }

                if (-not $policyExists) {
                    $validationFailures.Add("Insider Risk policy '$targetPolicyName'")
                }
            }
        }

        if ($validationFailures.Count -gt 0) {
            $failureSummary = ($validationFailures | Sort-Object -Unique) -join ', '
            throw "Post-deploy validation failed. Missing or inaccessible objects: $failureSummary"
        }

        foreach ($validationWarning in @($validationWarnings | Sort-Object -Unique)) {
            Write-LabLog -Message $validationWarning -Level Warning
        }

        Write-LabLog -Message 'Post-deploy validation passed for groups/policies/cases/rules in deployed workloads.' -Level Success
    }
    elseif ($WhatIfPreference) {
        Write-LabLog -Message 'Skipping post-deploy validation in WhatIf mode.' -Level Info
    }
    elseif ($SkipAuth) {
        Write-LabLog -Message 'Skipping post-deploy validation because authentication is disabled (-SkipAuth).' -Level Warning
    }

    # Summary
    $configuredWorkloads = @($Config.workloads.PSObject.Properties.Name)
    $disabledWorkloads = @(
        $configuredWorkloads | Where-Object { -not [bool]$Config.workloads.$_.enabled }
    )
    $successfulWorkloads = @($deployedWorkloads | Sort-Object -Unique)
    $errorSkippedWorkloads = @($failedWorkloads | Sort-Object -Unique)

    $deployedCount = $manifest.Keys.Count
    Write-LabStep -StepName 'Summary' -Description 'Deployment complete'
    Write-LabLog -Message "Workloads deployed: $deployedCount" -Level Info
    if ($successfulWorkloads.Count -gt 0) {
        Write-LabLog -Message "Workloads deployed successfully: $($successfulWorkloads -join ', ')" -Level Info
    }
    if ($manifestPath) {
        Write-LabLog -Message "Manifest: $manifestPath" -Level Info
    }
    if ($errorSkippedWorkloads.Count -gt 0) {
        Write-LabLog -Message "Workloads skipped due to error: $($errorSkippedWorkloads -join ', ')" -Level Warning
        Write-LabLog -Message "Re-run to retry failed workloads." -Level Warning
    }
    if ($disabledWorkloads.Count -gt 0) {
        Write-LabLog -Message "Workloads skipped by config: $($disabledWorkloads -join ', ')" -Level Info
    }
    if ($errorSkippedWorkloads.Count -eq 0) {
        Write-LabLog -Message 'Deploy-Lab finished successfully.' -Level Success
    }
}
catch {
    Write-LabLog -Message "Deploy-Lab failed: $_" -Level Error
    Write-LabLog -Message $_.ScriptStackTrace -Level Error
    throw
}
finally {
    if (-not $SkipAuth) {
        Disconnect-LabServices
    }
    Complete-LabLogging
}
