#Requires -Version 7.0

<#
.SYNOPSIS
    DLP workload module for purview-lab-deployer.
#>

$script:LocationParamMap = @{
    'Exchange'   = 'ExchangeLocation'
    'SharePoint' = 'SharePointLocation'
    'OneDrive'   = 'OneDriveLocation'
    'Teams'      = 'TeamsLocation'
}

function Deploy-DLP {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $createdPolicies = [System.Collections.Generic.List[string]]::new()
    $createdRules = [System.Collections.Generic.List[string]]::new()

    foreach ($policy in $Config.workloads.dlp.policies) {
        $policyName = "$($Config.prefix)-$($policy.name)"

        # Check if policy exists
        $existing = $null
        try {
            $existing = Get-DlpCompliancePolicy -Identity $policyName -ErrorAction Stop
        }
        catch {
            # Policy does not exist
        }

        if ($existing) {
            Write-LabLog -Message "DLP policy already exists: $policyName" -Level Info
        }
        elseif ($PSCmdlet.ShouldProcess($policyName, 'Create DLP policy')) {
            $locationParams = @{}
            foreach ($loc in $policy.locations) {
                $paramName = $script:LocationParamMap[$loc]
                if ($paramName) {
                    $locationParams[$paramName] = 'All'
                }
            }

            New-DlpCompliancePolicy -Name $policyName @locationParams -ErrorAction Stop | Out-Null
            Write-LabLog -Message "Created DLP policy: $policyName" -Level Success
        }

        $createdPolicies.Add($policyName)

        # --- Rules ---
        foreach ($rule in $policy.rules) {
            $ruleName = "$($Config.prefix)-$($rule.name)"

            $existingRule = $null
            try {
                $existingRule = Get-DlpComplianceRule -Identity $ruleName -ErrorAction Stop
            }
            catch {
                # Rule does not exist
            }

            if ($existingRule) {
                Write-LabLog -Message "DLP rule already exists: $ruleName" -Level Info
                $createdRules.Add($ruleName)
                continue
            }

            if ($PSCmdlet.ShouldProcess($ruleName, 'Create DLP rule')) {
                $sitArray = @()
                foreach ($sit in $rule.sensitiveInfoTypes) {
                    $sitArray += @{
                        name     = $sit
                        minCount = [string]$rule.minCount
                    }
                }

                New-DlpComplianceRule -Name $ruleName `
                    -Policy $policyName `
                    -ContentContainsSensitiveInformation $sitArray `
                    -ErrorAction Stop | Out-Null
                Write-LabLog -Message "Created DLP rule: $ruleName" -Level Success
            }

            $createdRules.Add($ruleName)
        }
    }

    return @{
        policies = $createdPolicies.ToArray()
        rules    = $createdRules.ToArray()
    }
}

function Remove-DLP {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    # Remove rules first (rules depend on policies)
    foreach ($policy in $Config.workloads.dlp.policies) {
        $policyName = "$($Config.prefix)-$($policy.name)"

        foreach ($rule in $policy.rules) {
            $ruleName = "$($Config.prefix)-$($rule.name)"

            $existing = $null
            try {
                $existing = Get-DlpComplianceRule -Identity $ruleName -ErrorAction Stop
            }
            catch {
                # Rule does not exist
            }

            if (-not $existing) {
                Write-LabLog -Message "DLP rule not found, skipping: $ruleName" -Level Warning
                continue
            }

            if ($PSCmdlet.ShouldProcess($ruleName, 'Remove DLP rule')) {
                Remove-DlpComplianceRule -Identity $ruleName -Confirm:$false
                Write-LabLog -Message "Removed DLP rule: $ruleName" -Level Success
            }
        }

        # Remove policy
        $existingPolicy = $null
        try {
            $existingPolicy = Get-DlpCompliancePolicy -Identity $policyName -ErrorAction Stop
        }
        catch {
            # Policy does not exist
        }

        if (-not $existingPolicy) {
            Write-LabLog -Message "DLP policy not found, skipping: $policyName" -Level Warning
            continue
        }

        if ($PSCmdlet.ShouldProcess($policyName, 'Remove DLP policy')) {
            Remove-DlpCompliancePolicy -Identity $policyName -Confirm:$false
            Write-LabLog -Message "Removed DLP policy: $policyName" -Level Success
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-DLP'
    'Remove-DLP'
)
