#Requires -Version 7.0

<#
.SYNOPSIS
    Communication Compliance workload module for purview-lab-deployer.
#>

function Deploy-CommunicationCompliance {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $policies = $Config.workloads.communicationCompliance.policies
    $manifestPolicies = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($policy in $policies) {
        $name = "$($Config.prefix)-$($policy.name)"
        $ruleName = "$name-Rule"

        Write-LabLog -Message "Processing communication compliance policy: $name" -Level Info

        # --- Policy ---
        $existing = $null
        try {
            $existing = Get-SupervisoryReviewPolicyV2 -Identity $name -ErrorAction SilentlyContinue
        }
        catch {
            # Policy does not exist
        }

        if (-not $existing) {
            if ($PSCmdlet.ShouldProcess($name, 'New-SupervisoryReviewPolicyV2')) {
                Write-LabLog -Message "Creating communication compliance policy: $name" -Level Info
                New-SupervisoryReviewPolicyV2 -Name $name -Reviewers $policy.reviewers -Comment 'Created by purview-lab-deployer' | Out-Null
            }
        }
        else {
            Write-LabLog -Message "Communication compliance policy already exists: $name" -Level Info
        }

        # --- Rule ---
        if ($PSCmdlet.ShouldProcess($ruleName, 'New-SupervisoryReviewRule')) {
            Write-LabLog -Message "Creating communication compliance rule: $ruleName" -Level Info

            $ruleParams = @{
                Name         = $ruleName
                Policy       = $name
                SamplingRate = 100
                Condition    = $policy.condition
            }

            if ($policy.supervisedUsers) {
                $ruleParams['SamplingRate'] = 100
                # Supervised users define the scope of monitored users
                New-SupervisoryReviewRule @ruleParams | Out-Null

                # Set supervised users on the policy after rule creation
                try {
                    Set-SupervisoryReviewPolicyV2 -Identity $name -AddReviewUser $policy.supervisedUsers -ErrorAction SilentlyContinue
                }
                catch {
                    Write-LabLog -Message "Could not set supervised users on $name`: $_" -Level Warning
                }
            }
            else {
                New-SupervisoryReviewRule @ruleParams | Out-Null
            }
        }

        $manifestPolicies.Add([PSCustomObject]@{
            policyName     = $name
            ruleName       = $ruleName
            reviewers      = $policy.reviewers
            supervisedUsers = $policy.supervisedUsers
        })
    }

    return [PSCustomObject]@{
        policies = $manifestPolicies.ToArray()
    }
}

function Remove-CommunicationCompliance {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    $policies = $Config.workloads.communicationCompliance.policies

    foreach ($policy in $policies) {
        $name = "$($Config.prefix)-$($policy.name)"
        $ruleName = "$name-Rule"

        Write-LabLog -Message "Removing communication compliance resources for policy: $name" -Level Info

        # --- Remove rule first ---
        try {
            $existing = Get-SupervisoryReviewPolicyV2 -Identity $name -ErrorAction SilentlyContinue
            if ($existing) {
                if ($PSCmdlet.ShouldProcess($ruleName, 'Remove-SupervisoryReviewRule')) {
                    Write-LabLog -Message "Removing communication compliance rule: $ruleName" -Level Info
                    Remove-SupervisoryReviewRule -Identity $ruleName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
        catch {
            Write-LabLog -Message "Communication compliance rule not found or already removed: $ruleName" -Level Warning
        }

        # --- Remove policy ---
        try {
            $existing = Get-SupervisoryReviewPolicyV2 -Identity $name -ErrorAction SilentlyContinue
            if ($existing) {
                if ($PSCmdlet.ShouldProcess($name, 'Remove-SupervisoryReviewPolicyV2')) {
                    Write-LabLog -Message "Removing communication compliance policy: $name" -Level Info
                    Remove-SupervisoryReviewPolicyV2 -Identity $name -Confirm:$false | Out-Null
                }
            }
        }
        catch {
            Write-LabLog -Message "Communication compliance policy not found or already removed: $name" -Level Warning
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-CommunicationCompliance'
    'Remove-CommunicationCompliance'
)
