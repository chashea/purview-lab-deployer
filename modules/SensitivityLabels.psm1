#Requires -Version 7.0

<#
.SYNOPSIS
    Sensitivity labels and auto-labeling policy module for purview-lab-deployer.
#>

function Deploy-SensitivityLabels {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $manifest = [ordered]@{
        labels           = @()
        autoLabelPolicies = @()
    }

    $labelConfig = $Config.workloads.sensitivityLabels

    # --- Deploy parent labels and sublabels ---
    foreach ($label in $labelConfig.labels) {
        $parentName = "$($Config.prefix)-$($label.name)"

        $existingLabel = $null
        try {
            $existingLabel = Get-Label -Identity $parentName -ErrorAction Stop
        }
        catch {
            $null = $_ # Label does not exist
        }

        if ($existingLabel -and $existingLabel.Mode -eq 'PendingDeletion') {
            Write-LabLog "Label '$parentName' is in PendingDeletion state. Cannot modify. Wait for deletion to complete and re-run." -Level Error
            throw "Label '$parentName' is in PendingDeletion state. Please wait and retry."
        }

        if ($existingLabel) {
            Write-LabLog "Label already exists: $parentName (IsLabelGroup=$($existingLabel.IsLabelGroup))" -Level Info
        }
        else {
            if ($PSCmdlet.ShouldProcess($parentName, 'Create sensitivity label group')) {
                New-Label `
                    -Name $parentName `
                    -DisplayName $parentName `
                    -Tooltip $label.tooltip `
                    -Comment "Created by purview-lab-deployer" `
                    -IsLabelGroup `
                    -ErrorAction Stop | Out-Null

                Write-LabLog "Created label group: $parentName" -Level Success
            }
        }

        $parentEntry = [ordered]@{
            name      = $parentName
            sublabels = @()
        }

        # Get parent label ID for sublabel creation
        $parentLabel = $null
        try {
            $parentLabel = Get-Label -Identity $parentName -ErrorAction Stop
        }
        catch {
            Write-LabLog "Could not retrieve parent label $parentName for sublabel creation" -Level Warning
        }

        foreach ($sublabel in $label.sublabels) {
            $sublabelIdentity = "$($Config.prefix)-$($label.name)-$($sublabel.name)" -replace ' ', '-'
            $sublabelDisplay = "$($Config.prefix)-$($label.name)-$($sublabel.name)"

            $sublabelExists = $false
            try {
                Get-Label -Identity $sublabelIdentity -ErrorAction Stop | Out-Null
                $sublabelExists = $true
                Write-LabLog "Sublabel already exists: $sublabelIdentity" -Level Info
            }
            catch {
                Write-LabLog "Sublabel not found, will create: $sublabelIdentity" -Level Info
            }

            if (-not $sublabelExists -and $null -ne $parentLabel) {
                if ($PSCmdlet.ShouldProcess($sublabelIdentity, 'Create sensitivity sublabel')) {
                    try {
                        New-Label `
                            -Name $sublabelIdentity `
                            -DisplayName $sublabelDisplay `
                            -ParentId $parentLabel.Guid `
                            -Tooltip $sublabel.tooltip `
                            -ContentType "File,Email" `
                            -ErrorAction Stop | Out-Null

                        Write-LabLog "Created sublabel: $sublabelIdentity" -Level Success

                        # Apply encryption settings
                        if ($sublabel.encryption) {
                            Set-Label -Identity $sublabelIdentity `
                                -EncryptionEnabled $true `
                                -EncryptionProtectionType 'Template' `
                                -ErrorAction Stop | Out-Null

                            Write-LabLog "Enabled encryption on sublabel: $sublabelIdentity" -Level Success
                        }

                        # Apply content marking settings
                        if ($sublabel.contentMarking) {
                            $markingParams = @{
                                Identity = $sublabelIdentity
                            }

                            if ($sublabel.contentMarking.headerText) {
                                $markingParams['ApplyContentMarkingHeaderEnabled'] = $true
                                $markingParams['ApplyContentMarkingHeaderText'] = $sublabel.contentMarking.headerText
                                $markingParams['ApplyContentMarkingHeaderFontSize'] = 10
                                $markingParams['ApplyContentMarkingHeaderFontColor'] = '#000000'
                                $markingParams['ApplyContentMarkingHeaderAlignment'] = 'Center'
                            }

                            if ($sublabel.contentMarking.footerText) {
                                $markingParams['ApplyContentMarkingFooterEnabled'] = $true
                                $markingParams['ApplyContentMarkingFooterText'] = $sublabel.contentMarking.footerText
                                $markingParams['ApplyContentMarkingFooterFontSize'] = 8
                                $markingParams['ApplyContentMarkingFooterFontColor'] = '#000000'
                            }

                            Set-Label @markingParams -ErrorAction Stop | Out-Null
                            Write-LabLog "Applied content marking on sublabel: $sublabelIdentity" -Level Success
                        }
                    }
                    catch {
                        Write-LabLog "Failed to create sublabel $sublabelIdentity`: $_" -Level Error
                        throw
                    }
                }
            }

            $parentEntry.sublabels += $sublabelIdentity
        }

        $manifest.labels += [PSCustomObject]$parentEntry
    }

    # --- Deploy auto-labeling policies ---
    foreach ($policy in $labelConfig.autoLabelPolicies) {
        $policyName = "$($Config.prefix)-$($policy.name)"

        $policyExists = $false
        try {
            Get-AutoSensitivityLabelPolicy -Identity $policyName -ErrorAction Stop | Out-Null
            $policyExists = $true
            Write-LabLog "Auto-label policy already exists: $policyName" -Level Info
        }
        catch {
            Write-LabLog "Auto-label policy not found, will create: $policyName" -Level Info
        }

        if (-not $policyExists) {
            if ($PSCmdlet.ShouldProcess($policyName, 'Create auto-sensitivity label policy')) {
                # Resolve the target label name with prefix
                $targetLabel = "$($Config.prefix)-$($policy.labelName)"

                $policyParams = @{
                    Name                 = $policyName
                    ApplySensitivityLabel = $targetLabel
                }

                foreach ($location in $policy.locations) {
                    switch ($location) {
                        'Exchange'   { $policyParams['ExchangeLocation'] = 'All' }
                        'SharePoint' { $policyParams['SharePointLocation'] = 'All' }
                        'OneDrive'   { $policyParams['OneDriveLocation'] = 'All' }
                    }
                }

                New-AutoSensitivityLabelPolicy @policyParams | Out-Null
                Write-LabLog "Created auto-label policy: $policyName" -Level Success

                # Create rule with sensitive information types
                $ruleName = "$policyName-rule"
                $sitArray = @()
                foreach ($sit in $policy.sensitiveInfoTypes) {
                    $sitArray += @{
                        Name           = $sit
                        MinCount       = 1
                        MaxConfidence  = 100
                        MinConfidence  = 75
                    }
                }

                New-AutoSensitivityLabelRule `
                    -Policy $policyName `
                    -Name $ruleName `
                    -ContentContainsSensitiveInformation $sitArray | Out-Null

                Write-LabLog "Created auto-label rule: $ruleName" -Level Success
            }
        }

        $manifest.autoLabelPolicies += [ordered]@{
            name     = $policyName
            ruleName = "$policyName-rule"
        }
    }

    return [PSCustomObject]$manifest
}

function Remove-SensitivityLabels {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest  # Reserved for manifest-based removal
    )

    $null = $Manifest  # Manifest-based removal not yet implemented

    $labelConfig = $Config.workloads.sensitivityLabels

    # --- Remove auto-label policies and rules first ---
    foreach ($policy in $labelConfig.autoLabelPolicies) {
        $policyName = "$($Config.prefix)-$($policy.name)"
        $ruleName = "$policyName-rule"

        # Remove rule
        try {
            Get-AutoSensitivityLabelRule -Policy $policyName -ErrorAction Stop | Out-Null
            if ($PSCmdlet.ShouldProcess($ruleName, 'Remove auto-sensitivity label rule')) {
                Remove-AutoSensitivityLabelRule -Identity $ruleName -Confirm:$false -ErrorAction Stop
                Write-LabLog "Removed auto-label rule: $ruleName" -Level Success
            }
        }
        catch {
            Write-LabLog "Auto-label rule not found or already removed: $ruleName" -Level Info
        }

        # Remove policy
        try {
            Get-AutoSensitivityLabelPolicy -Identity $policyName -ErrorAction Stop | Out-Null
            if ($PSCmdlet.ShouldProcess($policyName, 'Remove auto-sensitivity label policy')) {
                Remove-AutoSensitivityLabelPolicy -Identity $policyName -Confirm:$false -ErrorAction Stop
                Write-LabLog "Removed auto-label policy: $policyName" -Level Success
            }
        }
        catch {
            Write-LabLog "Auto-label policy not found or already removed: $policyName" -Level Info
        }
    }

    # --- Remove sublabels first, then parent labels (reverse order) ---
    $reversedLabels = @($labelConfig.labels)
    [array]::Reverse($reversedLabels)

    foreach ($label in $reversedLabels) {
        # Remove sublabels
        if ($label.sublabels) {
            $reversedSublabels = @($label.sublabels)
            [array]::Reverse($reversedSublabels)

            foreach ($sublabel in $reversedSublabels) {
                $sublabelIdentity = "$($Config.prefix)-$($label.name)-$($sublabel.name)" -replace ' ', '-'

                try {
                    Get-Label -Identity $sublabelIdentity -ErrorAction Stop | Out-Null
                    if ($PSCmdlet.ShouldProcess($sublabelIdentity, 'Remove sensitivity sublabel')) {
                        Remove-Label -Identity $sublabelIdentity -Confirm:$false -ErrorAction Stop
                        Write-LabLog "Removed sublabel: $sublabelIdentity" -Level Success
                    }
                }
                catch {
                    Write-LabLog "Sublabel not found or already removed: $sublabelIdentity" -Level Info
                }
            }
        }

        # Remove parent label
        $parentName = "$($Config.prefix)-$($label.name)"

        try {
            Get-Label -Identity $parentName -ErrorAction Stop | Out-Null
            if ($PSCmdlet.ShouldProcess($parentName, 'Remove sensitivity label')) {
                Remove-Label -Identity $parentName -Confirm:$false -ErrorAction Stop
                Write-LabLog "Removed label: $parentName" -Level Success
            }
        }
        catch {
            Write-LabLog "Label not found or already removed: $parentName" -Level Info
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-SensitivityLabels'
    'Remove-SensitivityLabels'
)
