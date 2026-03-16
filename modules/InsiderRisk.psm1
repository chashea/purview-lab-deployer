#Requires -Version 7.0

<#
.SYNOPSIS
    Insider Risk Management workload module for purview-lab-deployer.
    Uses Microsoft Graph beta API via Invoke-MgGraphRequest.
#>

function Deploy-InsiderRisk {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $createdPolicies = [System.Collections.Generic.List[hashtable]]::new()
    $createdPriorityGroups = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($policy in $Config.workloads.insiderRisk.policies) {
        $name = "$($Config.prefix)-$($policy.name)"

        # --- Priority User Groups ---
        foreach ($groupName in $policy.priorityUserGroups) {
            try {
                $existingGroups = Invoke-MgGraphRequest -Method GET `
                    -Uri '/beta/security/insiderRiskManagement/priorityUserGroups'
                $priorityGroup = $existingGroups.value | Where-Object { $_.displayName -eq $groupName }

                if (-not $priorityGroup) {
                    if ($PSCmdlet.ShouldProcess($groupName, 'Create priority user group')) {
                        $priorityGroup = Invoke-MgGraphRequest -Method POST `
                            -Uri '/beta/security/insiderRiskManagement/priorityUserGroups' `
                            -Body @{ displayName = $groupName }
                        Write-LabLog -Message "Created priority user group: $groupName" -Level Success
                    }
                }
                else {
                    Write-LabLog -Message "Priority user group already exists: $groupName" -Level Info
                }

                # Resolve members from the matching Microsoft 365 / security group
                if ($priorityGroup) {
                    $mgGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
                    if ($mgGroup) {
                        $members = Get-MgGroupMember -GroupId $mgGroup.Id -All -ErrorAction SilentlyContinue
                        foreach ($member in $members) {
                            try {
                                Invoke-MgGraphRequest -Method POST `
                                    -Uri "/beta/security/insiderRiskManagement/priorityUserGroups/$($priorityGroup.id)/members/`$ref" `
                                    -Body @{ '@odata.id' = "https://graph.microsoft.com/beta/users/$($member.Id)" }
                                Write-LabLog -Message "Added member $($member.Id) to priority group $groupName" -Level Info
                            }
                            catch {
                                Write-LabLog -Message "Could not add member $($member.Id) to $groupName`: $($_.Exception.Message)" -Level Warning
                            }
                        }
                    }
                    else {
                        Write-LabLog -Message "MgGroup not found for priority user group: $groupName" -Level Warning
                    }

                    $createdPriorityGroups.Add(@{
                        id          = $priorityGroup.id
                        displayName = $groupName
                    })
                }
            }
            catch {
                Write-LabLog -Message "Error processing priority user group $groupName`: $($_.Exception.Message)" -Level Warning
            }
        }

        # --- Policy ---
        try {
            $existingPolicies = Invoke-MgGraphRequest -Method GET `
                -Uri '/beta/security/insiderRiskManagement/policies'
            $existing = $existingPolicies.value | Where-Object { $_.displayName -eq $name }

            if ($existing) {
                Write-LabLog -Message "Insider Risk policy already exists: $name" -Level Info
                $createdPolicies.Add(@{
                    id          = $existing.id
                    displayName = $name
                    template    = $policy.template
                })
                continue
            }

            if ($PSCmdlet.ShouldProcess($name, 'Create Insider Risk policy')) {
                $body = @{
                    displayName               = $name
                    insiderRiskPolicyTemplate  = $policy.template
                    isEnabled                  = $true
                }

                $created = Invoke-MgGraphRequest -Method POST `
                    -Uri '/beta/security/insiderRiskManagement/policies' `
                    -Body $body

                Write-LabLog -Message "Created Insider Risk policy: $name (template: $($policy.template))" -Level Success
                $createdPolicies.Add(@{
                    id          = $created.id
                    displayName = $name
                    template    = $policy.template
                })
            }
        }
        catch {
            Write-LabLog -Message "Error creating Insider Risk policy $name`: $($_.Exception.Message)" -Level Warning
        }
    }

    return @{
        policies       = $createdPolicies.ToArray()
        priorityGroups = $createdPriorityGroups.ToArray()
    }
}

function Remove-InsiderRisk {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    # --- Remove policies ---
    foreach ($policy in $Config.workloads.insiderRisk.policies) {
        $name = "$($Config.prefix)-$($policy.name)"

        try {
            $existingPolicies = Invoke-MgGraphRequest -Method GET `
                -Uri '/beta/security/insiderRiskManagement/policies'
            $existing = $existingPolicies.value | Where-Object { $_.displayName -eq $name }

            if (-not $existing) {
                Write-LabLog -Message "Insider Risk policy not found, skipping: $name" -Level Warning
                continue
            }

            if ($PSCmdlet.ShouldProcess($name, 'Remove Insider Risk policy')) {
                Invoke-MgGraphRequest -Method DELETE `
                    -Uri "/beta/security/insiderRiskManagement/policies/$($existing.id)"
                Write-LabLog -Message "Removed Insider Risk policy: $name" -Level Success
            }
        }
        catch {
            Write-LabLog -Message "Error removing Insider Risk policy $name`: $($_.Exception.Message)" -Level Warning
        }
    }

    # --- Remove priority user groups ---
    $removedGroupNames = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($policy in $Config.workloads.insiderRisk.policies) {
        foreach ($groupName in $policy.priorityUserGroups) {
            if ($removedGroupNames.Contains($groupName)) { continue }

            try {
                $existingGroups = Invoke-MgGraphRequest -Method GET `
                    -Uri '/beta/security/insiderRiskManagement/priorityUserGroups'
                $existing = $existingGroups.value | Where-Object { $_.displayName -eq $groupName }

                if (-not $existing) {
                    Write-LabLog -Message "Priority user group not found, skipping: $groupName" -Level Warning
                    $removedGroupNames.Add($groupName) | Out-Null
                    continue
                }

                if ($PSCmdlet.ShouldProcess($groupName, 'Remove priority user group')) {
                    Invoke-MgGraphRequest -Method DELETE `
                        -Uri "/beta/security/insiderRiskManagement/priorityUserGroups/$($existing.id)"
                    Write-LabLog -Message "Removed priority user group: $groupName" -Level Success
                }
            }
            catch {
                Write-LabLog -Message "Error removing priority user group $groupName`: $($_.Exception.Message)" -Level Warning
            }

            $removedGroupNames.Add($groupName) | Out-Null
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-InsiderRisk'
    'Remove-InsiderRisk'
)
