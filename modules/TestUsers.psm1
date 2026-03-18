#Requires -Version 7.0

<#
.SYNOPSIS
    Test users and groups workload module for purview-lab-deployer.
#>

function Deploy-TestUsers {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $createdUpns = [System.Collections.Generic.List[string]]::new()
    $createdGroups = [System.Collections.Generic.List[string]]::new()

    $graphContext = Get-MgContext
    if (-not $graphContext -or [string]::IsNullOrWhiteSpace($graphContext.Account)) {
        throw 'Microsoft Graph context is not available for Deploy-TestUsers.'
    }

    # --- Users ---
    foreach ($user in $Config.workloads.testUsers.users) {
        $upn = "$($user.mailNickname)@$($Config.domain)"

        $existing = Get-LabUserByIdentity -Identity $upn -DefaultDomain $Config.domain
        if ($existing) {
            $existingUpn = [string]$existing.UserPrincipalName
            Write-LabLog -Message "User already exists: $existingUpn" -Level Info
            $createdUpns.Add($existingUpn)
            continue
        }

        if ($PSCmdlet.ShouldProcess($upn, 'Create user')) {
            $password = "PVLab-$((New-Guid).ToString().Substring(0,8))!"
            $passwordProfile = @{
                ForceChangePasswordNextSignIn = $true
                Password                     = $password
            }

            $params = @{
                DisplayName       = $user.displayName
                MailNickname      = $user.mailNickname
                UserPrincipalName = $upn
                Department        = $user.department
                JobTitle          = $user.jobTitle
                UsageLocation     = $user.usageLocation
                AccountEnabled    = $true
                PasswordProfile   = $passwordProfile
            }

            New-MgUser @params -ErrorAction Stop | Out-Null
            $resolvedUser = $null
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                $resolvedUser = Get-LabUserByIdentity -Identity $upn -DefaultDomain $Config.domain
                if ($resolvedUser) {
                    break
                }

                if ($attempt -lt 6) {
                    Start-Sleep -Seconds 5
                }
            }

            if (-not $resolvedUser) {
                throw "Created user '$upn' could not be confirmed in Microsoft Graph."
            }

            $resolvedUpn = [string]$resolvedUser.UserPrincipalName
            Write-LabLog -Message "Created user: $resolvedUpn" -Level Success
            $createdUpns.Add($resolvedUpn)
        }
    }

    # --- License assignment ---
    # Auto-detect a SKU with Exchange mailbox capability and available units
    $skus = Get-MgSubscribedSku -ErrorAction Stop
    $exchangePlanIds = @(
        '9aaf7827-d63c-4b61-89c3-182f06f82b13'  # EXCHANGE_S_ENTERPRISE (Plan 2)
        'efb87545-963c-4e0d-99df-69c6916d9eb0'  # EXCHANGE_S_STANDARD (Plan 1)
        '80873e7a-cd2a-4e67-b061-1b5381571571'  # EXCHANGE_S_FOUNDATION
        '113feb6c-3fe4-4440-bddc-54d774bf0318'  # EXCHANGE_S_ENTERPRISE_GOV
    )
    $mailboxSku = $skus | Where-Object {
        $_.PrepaidUnits.Enabled -gt $_.ConsumedUnits -and
        ($_.ServicePlans | Where-Object { $exchangePlanIds -contains $_.ServicePlanId })
    } | Select-Object -First 1

    if ($mailboxSku) {
        Write-LabLog -Message "Auto-detected license SKU: $($mailboxSku.SkuPartNumber) ($($mailboxSku.SkuId)) — $($mailboxSku.PrepaidUnits.Enabled - $mailboxSku.ConsumedUnits) available" -Level Info

        foreach ($upn in $createdUpns) {
            $userObj = Get-MgUser -Filter "userPrincipalName eq '$upn'" -Property Id,AssignedLicenses -ErrorAction SilentlyContinue
            if (-not $userObj) { continue }

            $alreadyLicensed = $userObj.AssignedLicenses | Where-Object { $_.SkuId -eq $mailboxSku.SkuId }
            if ($alreadyLicensed) {
                Write-LabLog -Message "License already assigned to $upn" -Level Info
                continue
            }

            if ($PSCmdlet.ShouldProcess($upn, "Assign license $($mailboxSku.SkuPartNumber)")) {
                Set-MgUserLicense -UserId $userObj.Id -AddLicenses @(@{ SkuId = $mailboxSku.SkuId }) -RemoveLicenses @() -ErrorAction Stop | Out-Null
                Write-LabLog -Message "Assigned license $($mailboxSku.SkuPartNumber) to $upn" -Level Success
            }
        }
    }
    else {
        Write-LabLog -Message 'No SKU with Exchange mailbox capability and available units found. Users will not have mailboxes until licensed manually.' -Level Warning
    }

    # --- Groups ---
    foreach ($group in $Config.workloads.testUsers.groups) {
        $groupName = $group.displayName
        $mailNickname = $groupName -replace '[^a-zA-Z0-9-]', ''

        $existing = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
        if ($existing) {
            Write-LabLog -Message "Group already exists: $groupName" -Level Info
            $createdGroups.Add($groupName)
            continue
        }

        if ($PSCmdlet.ShouldProcess($groupName, 'Create group')) {
            $newGroup = New-MgGroup -DisplayName $groupName `
                -SecurityEnabled:$true `
                -MailEnabled:$false `
                -MailNickname $mailNickname `
                -ErrorAction Stop

            Write-LabLog -Message "Created group: $groupName" -Level Success

            # Add members
            foreach ($memberNickname in $group.members) {
                $memberUser = Get-LabUserByIdentity -Identity $memberNickname -DefaultDomain $Config.domain
                if ($memberUser) {
                    $memberUpn = [string]$memberUser.UserPrincipalName
                    New-MgGroupMember -GroupId $newGroup.Id `
                        -DirectoryObjectId $memberUser.Id `
                        -ErrorAction Stop
                    Write-LabLog -Message "Added $memberUpn to group $groupName" -Level Info
                }
                else {
                    Write-LabLog -Message "Member not found, skipping: $memberNickname@$($Config.domain)" -Level Warning
                }
            }

            $createdGroups.Add($groupName)
        }
    }

    return @{
        users  = $createdUpns.ToArray()
        groups = $createdGroups.ToArray()
    }
}

function Remove-TestUsers {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest  # Reserved for manifest-based removal
    )

    $targetGroups = @()
    $targetUsers = @()

    $graphContext = Get-MgContext
    if (-not $graphContext -or [string]::IsNullOrWhiteSpace($graphContext.Account)) {
        throw 'Microsoft Graph context is not available for Remove-TestUsers.'
    }

    if ($Manifest) {
        foreach ($groupName in @($Manifest.groups)) {
            if (-not [string]::IsNullOrWhiteSpace($groupName)) {
                $targetGroups += [string]$groupName
            }
        }
        foreach ($upn in @($Manifest.users)) {
            if (-not [string]::IsNullOrWhiteSpace($upn)) {
                $targetUsers += [string]$upn
            }
        }
    }

    if ($targetGroups.Count -eq 0) {
        foreach ($group in $Config.workloads.testUsers.groups) {
            $targetGroups += [string]$group.displayName
        }
    }

    if ($targetUsers.Count -eq 0) {
        foreach ($user in $Config.workloads.testUsers.users) {
            $targetUsers += "$($user.mailNickname)@$($Config.domain)"
        }
    }

    $targetGroups = @($targetGroups | Sort-Object -Unique)
    $targetUsers = @($targetUsers | Sort-Object -Unique)

    # Remove groups first (reverse dependency order)
    foreach ($groupName in $targetGroups) {

        $existing = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
        if (-not $existing) {
            Write-LabLog -Message "Group not found, skipping: $groupName" -Level Warning
            continue
        }

        if ($PSCmdlet.ShouldProcess($groupName, 'Remove group')) {
            Remove-MgGroup -GroupId $existing.Id -ErrorAction Stop
            Write-LabLog -Message "Removed group: $groupName" -Level Success
        }
    }

    # Remove users
    foreach ($upn in $targetUsers) {
        $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
        if (-not $existing) {
            Write-LabLog -Message "User not found, skipping: $upn" -Level Warning
            continue
        }

        if ($PSCmdlet.ShouldProcess($upn, 'Remove user')) {
            Remove-MgUser -UserId $existing.Id -ErrorAction Stop
            Write-LabLog -Message "Removed user: $upn" -Level Success
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-TestUsers'
    'Remove-TestUsers'
)
