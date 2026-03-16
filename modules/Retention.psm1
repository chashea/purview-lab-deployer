#Requires -Version 7.0

<#
.SYNOPSIS
    Retention policies module for purview-lab-deployer.
#>

function Deploy-Retention {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $manifest = [ordered]@{
        policies = @()
    }

    $retentionConfig = $Config.workloads.retention

    foreach ($policy in $retentionConfig.policies) {
        $policyName = "$($Config.prefix)-$($policy.name)"

        $policyExists = $false
        try {
            Get-RetentionCompliancePolicy -Identity $policyName -ErrorAction Stop | Out-Null
            $policyExists = $true
            Write-LabLog "Retention policy already exists: $policyName" -Level Info
        }
        catch {
            Write-LabLog "Retention policy not found, will create: $policyName" -Level Info
        }

        if (-not $policyExists) {
            if ($PSCmdlet.ShouldProcess($policyName, 'Create retention compliance policy')) {
                $policyParams = @{
                    Name = $policyName
                }

                foreach ($location in $policy.locations) {
                    switch ($location) {
                        'Exchange'   { $policyParams['ExchangeLocation'] = 'All' }
                        'SharePoint' { $policyParams['SharePointLocation'] = 'All' }
                        'OneDrive'   { $policyParams['OneDriveLocation'] = 'All' }
                    }
                }

                New-RetentionCompliancePolicy @policyParams | Out-Null
                Write-LabLog "Created retention policy: $policyName" -Level Success

                # Map config action to compliance action
                $complianceAction = switch ($policy.retentionAction) {
                    'retainAndDelete' { 'KeepAndDelete' }
                    'retainOnly'      { 'Keep' }
                    default           { 'KeepAndDelete' }
                }

                $ruleName = "$policyName-rule"
                New-RetentionComplianceRule `
                    -Policy $policyName `
                    -Name $ruleName `
                    -RetentionDuration $policy.retentionDays `
                    -RetentionComplianceAction $complianceAction | Out-Null

                Write-LabLog "Created retention rule: $ruleName (${complianceAction}, $($policy.retentionDays) days)" -Level Success
            }
        }

        $manifest.policies += [ordered]@{
            name     = $policyName
            ruleName = "$policyName-rule"
        }
    }

    return [PSCustomObject]$manifest
}

function Remove-Retention {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    $retentionConfig = $Config.workloads.retention

    foreach ($policy in $retentionConfig.policies) {
        $policyName = "$($Config.prefix)-$($policy.name)"

        # Remove rules first
        try {
            $rules = Get-RetentionComplianceRule -Policy $policyName -ErrorAction Stop
            foreach ($rule in $rules) {
                if ($PSCmdlet.ShouldProcess($rule.Name, 'Remove retention compliance rule')) {
                    Remove-RetentionComplianceRule -Identity $rule.Name -Confirm:$false -ErrorAction Stop
                    Write-LabLog "Removed retention rule: $($rule.Name)" -Level Success
                }
            }
        }
        catch {
            Write-LabLog "Retention rules not found or already removed for policy: $policyName" -Level Info
        }

        # Remove policy
        try {
            Get-RetentionCompliancePolicy -Identity $policyName -ErrorAction Stop | Out-Null
            if ($PSCmdlet.ShouldProcess($policyName, 'Remove retention compliance policy')) {
                Remove-RetentionCompliancePolicy -Identity $policyName -Confirm:$false -ErrorAction Stop
                Write-LabLog "Removed retention policy: $policyName" -Level Success
            }
        }
        catch {
            Write-LabLog "Retention policy not found or already removed: $policyName" -Level Info
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-Retention'
    'Remove-Retention'
)
