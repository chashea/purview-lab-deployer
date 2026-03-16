#Requires -Version 7.0

<#
.SYNOPSIS
    Communication Compliance workload module for purview-lab-deployer.
.DESCRIPTION
    Uses New-FeatureConfiguration with FeatureScenario KnowYourData to create
    DSPM for AI collection policies. The retired SupervisoryReviewPolicyV2 cmdlets
    are no longer available in the SCC module.
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

        Write-LabLog -Message "Processing DSPM for AI collection policy: $name" -Level Info

        # Check if a KnowYourData feature config with this name already exists
        $existing = $null
        try {
            $existing = Get-FeatureConfiguration -FeatureScenario KnowYourData -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $name }
        }
        catch {
            # Config does not exist
        }

        if (-not $existing) {
            if ($PSCmdlet.ShouldProcess($name, 'New-FeatureConfiguration -FeatureScenario KnowYourData')) {
                Write-LabLog -Message "Creating DSPM for AI collection policy: $name" -Level Info

                $scenarioConfig = @{
                    Activities        = @('UploadText', 'DownloadText')
                    SensitiveTypeIds  = @('All')
                    IsIngestionEnabled = $true
                } | ConvertTo-Json -Compress

                $locationsArray = @(
                    @{
                        Workload       = 'Applications'
                        Location       = 'All'
                        LocationSource = 'Entra'
                        LocationType   = 'Group'
                        Inclusions     = @(
                            @{
                                Type     = 'Tenant'
                                Identity = 'All'
                            }
                        )
                    }
                )
                $locations = "[$($locationsArray | ConvertTo-Json -Depth 4 -Compress)]"

                New-FeatureConfiguration `
                    -FeatureScenario KnowYourData `
                    -Name $name `
                    -Mode Enable `
                    -ScenarioConfig $scenarioConfig `
                    -Locations $locations `
                    -ErrorAction Stop | Out-Null

                Write-LabLog -Message "Created DSPM for AI collection policy: $name" -Level Info
                Write-LabLog -Message (
                    "NOTE: Full Communication Compliance policy review/remediation " +
                    "configuration requires the Microsoft Purview portal " +
                    "(DSPM for AI > Recommendations > 'Control Unethical Behavior in AI')"
                ) -Level Warning
            }
        }
        else {
            Write-LabLog -Message "DSPM for AI collection policy already exists: $name" -Level Info
        }

        $manifestPolicies.Add([PSCustomObject]@{
            policyName      = $name
            featureScenario = 'KnowYourData'
            reviewers       = $policy.reviewers
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

        Write-LabLog -Message "Removing DSPM for AI collection policy: $name" -Level Info

        $existing = $null
        try {
            $existing = Get-FeatureConfiguration -FeatureScenario KnowYourData -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $name }
        }
        catch {
            # Not found
        }

        if ($existing) {
            if ($PSCmdlet.ShouldProcess($name, 'Remove-FeatureConfiguration')) {
                try {
                    Remove-FeatureConfiguration -Identity $existing.Identity -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-LabLog -Message "Removed DSPM for AI collection policy: $name" -Level Info
                }
                catch {
                    Write-LabLog -Message "Failed to remove DSPM for AI collection policy $name`: $_" -Level Warning
                }
            }
        }
        else {
            Write-LabLog -Message "DSPM for AI collection policy not found (already removed): $name" -Level Info
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-CommunicationCompliance'
    'Remove-CommunicationCompliance'
)
