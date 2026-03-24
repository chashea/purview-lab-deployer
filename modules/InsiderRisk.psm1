#Requires -Version 7.0

<#
.SYNOPSIS
    Insider Risk Management workload module for purview-lab-deployer.
    Uses Security & Compliance PowerShell cmdlets (New/Get/Remove-InsiderRiskPolicy,
    New/Get/Remove-InsiderRiskEntityList).
#>

# Template-friendly name -> InsiderRiskScenario enum mapping
$script:TemplateToScenario = @{
    'Data theft by departing users' = 'IntellectualPropertyTheft'
    'Data leaks'                    = 'LeakOfInformation'
    'Risky AI usage'                = 'RiskyAIUsage'
}

function Deploy-InsiderRisk {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $createdPolicies = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($policy in $Config.workloads.insiderRisk.policies) {
        $name = "$($Config.prefix)-$($policy.name)"
        $priorityUserGroups = @()
        if ($policy.PSObject.Properties['priorityUserGroups'] -and $policy.priorityUserGroups) {
            $priorityUserGroups = @($policy.priorityUserGroups | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        }

        # Map config template to InsiderRiskScenario value
        $scenario = if ($script:TemplateToScenario.ContainsKey($policy.template)) {
            $script:TemplateToScenario[$policy.template]
        }
        else {
            $policy.template
        }

        try {
            $existing = Get-InsiderRiskPolicy -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $name }

            if ($existing) {
                Write-LabLog -Message "Insider Risk policy already exists: $name" -Level Info
                if ($priorityUserGroups.Count -gt 0) {
                    Write-LabLog -Message "Configured priority user groups for ${name}: $($priorityUserGroups -join ', ')" -Level Info
                }
                $createdPolicies.Add(@{
                    name               = $name
                    scenario           = $scenario
                    priorityUserGroups = $priorityUserGroups
                    status             = 'existing'
                })
                continue
            }

            if ($PSCmdlet.ShouldProcess($name, "Create Insider Risk policy (scenario: $scenario)")) {
                $policyParams = @{
                    Name                 = $name
                    InsiderRiskScenario  = $scenario
                    Enabled              = $true
                    ErrorAction          = 'Stop'
                }

                # Pass indicators if configured
                if ($policy.PSObject.Properties['indicators'] -and @($policy.indicators).Count -gt 0) {
                    $indicatorList = @($policy.indicators | ForEach-Object { [string]$_ })
                    $indicatorParam = $null
                    try {
                        $cmdInfo = Get-Command New-InsiderRiskPolicy -ErrorAction SilentlyContinue
                        if ($cmdInfo -and $cmdInfo.Parameters.ContainsKey('IndicatorsToEnable')) {
                            $indicatorParam = 'IndicatorsToEnable'
                        }
                        elseif ($cmdInfo -and $cmdInfo.Parameters.ContainsKey('Indicators')) {
                            $indicatorParam = 'Indicators'
                        }
                    }
                    catch { $null = $_ }

                    if ($indicatorParam) {
                        $policyParams[$indicatorParam] = $indicatorList
                        Write-LabLog -Message "Enabling indicators for ${name}: $($indicatorList -join ', ')" -Level Info
                    }
                    else {
                        Write-LabLog -Message "Policy '$name' has indicators configured but New-InsiderRiskPolicy does not support indicator parameters. Indicators must be enabled manually in the Purview portal." -Level Warning
                    }
                }

                # Pass thresholds if configured
                if ($policy.PSObject.Properties['thresholds'] -and -not [string]::IsNullOrWhiteSpace([string]$policy.thresholds)) {
                    try {
                        $cmdInfo = Get-Command New-InsiderRiskPolicy -ErrorAction SilentlyContinue
                        if ($cmdInfo -and $cmdInfo.Parameters.ContainsKey('ThresholdType')) {
                            $policyParams['ThresholdType'] = [string]$policy.thresholds
                        }
                    }
                    catch { $null = $_ }
                }

                New-InsiderRiskPolicy @policyParams

                Write-LabLog -Message "Created Insider Risk policy: $name (scenario: $scenario)" -Level Success
                if ($priorityUserGroups.Count -gt 0) {
                    Write-LabLog -Message "Configured priority user groups for ${name}: $($priorityUserGroups -join ', ')" -Level Info
                }
                $createdPolicies.Add(@{
                    name               = $name
                    scenario           = $scenario
                    priorityUserGroups = $priorityUserGroups
                    status             = 'created'
                })
            }
        }
        catch {
            Write-LabLog -Message "Error creating Insider Risk policy $name`: $($_.Exception.Message)" -Level Warning
        }
    }

    return @{
        policies = $createdPolicies.ToArray()
    }
}

function Remove-InsiderRisk {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest  # Reserved for manifest-based removal
    )

    $targetPolicyNames = @()

    if ($Manifest) {
        foreach ($manifestPolicy in @($Manifest.policies)) {
            if ($manifestPolicy -is [string]) {
                $targetPolicyNames += [string]$manifestPolicy
            }
            elseif ($manifestPolicy.name) {
                $targetPolicyNames += [string]$manifestPolicy.name
            }
        }
    }

    if ($targetPolicyNames.Count -eq 0) {
        foreach ($policy in $Config.workloads.insiderRisk.policies) {
            $targetPolicyNames += "$($Config.prefix)-$($policy.name)"
        }
    }

    $targetPolicyNames = @($targetPolicyNames | Sort-Object -Unique)

    foreach ($name in $targetPolicyNames) {

        try {
            $existing = Get-InsiderRiskPolicy -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $name }

            if (-not $existing) {
                Write-LabLog -Message "Insider Risk policy not found, skipping: $name" -Level Warning
                continue
            }

            if ($PSCmdlet.ShouldProcess($name, 'Remove Insider Risk policy')) {
                Remove-InsiderRiskPolicy -Name $name -ErrorAction Stop
                Write-LabLog -Message "Removed Insider Risk policy: $name" -Level Success
            }
        }
        catch {
            Write-LabLog -Message "Error removing Insider Risk policy $name`: $($_.Exception.Message)" -Level Warning
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-InsiderRisk'
    'Remove-InsiderRisk'
)
