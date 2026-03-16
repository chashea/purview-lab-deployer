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

    # --- Users ---
    foreach ($user in $Config.workloads.testUsers.users) {
        $upn = "$($user.mailNickname)@$($Config.domain)"

        $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-LabLog -Message "User already exists: $upn" -Level Info
            $createdUpns.Add($upn)
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

            New-MgUser @params | Out-Null
            Write-LabLog -Message "Created user: $upn" -Level Success
            $createdUpns.Add($upn)
        }
    }

    # --- Groups ---
    foreach ($group in $Config.workloads.testUsers.groups) {
        $groupName = $group.displayName
        $mailNickname = $groupName -replace '[^a-zA-Z0-9-]', ''

        $existing = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-LabLog -Message "Group already exists: $groupName" -Level Info
            $createdGroups.Add($groupName)
            continue
        }

        if ($PSCmdlet.ShouldProcess($groupName, 'Create group')) {
            $newGroup = New-MgGroup -DisplayName $groupName `
                -SecurityEnabled:$true `
                -MailEnabled:$false `
                -MailNickname $mailNickname

            Write-LabLog -Message "Created group: $groupName" -Level Success

            # Add members
            foreach ($memberNickname in $group.members) {
                $memberUpn = "$memberNickname@$($Config.domain)"
                $memberUser = Get-MgUser -Filter "userPrincipalName eq '$memberUpn'" -ErrorAction SilentlyContinue
                if ($memberUser) {
                    New-MgGroupMember -GroupId $newGroup.Id `
                        -DirectoryObjectId $memberUser.Id
                    Write-LabLog -Message "Added $memberUpn to group $groupName" -Level Info
                }
                else {
                    Write-LabLog -Message "Member not found, skipping: $memberUpn" -Level Warning
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

    $null = $Manifest  # Manifest-based removal not yet implemented

    # Remove groups first (reverse dependency order)
    foreach ($group in $Config.workloads.testUsers.groups) {
        $groupName = $group.displayName

        $existing = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-LabLog -Message "Group not found, skipping: $groupName" -Level Warning
            continue
        }

        if ($PSCmdlet.ShouldProcess($groupName, 'Remove group')) {
            Remove-MgGroup -GroupId $existing.Id
            Write-LabLog -Message "Removed group: $groupName" -Level Success
        }
    }

    # Remove users
    foreach ($user in $Config.workloads.testUsers.users) {
        $upn = "$($user.mailNickname)@$($Config.domain)"

        $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-LabLog -Message "User not found, skipping: $upn" -Level Warning
            continue
        }

        if ($PSCmdlet.ShouldProcess($upn, 'Remove user')) {
            Remove-MgUser -UserId $existing.Id
            Write-LabLog -Message "Removed user: $upn" -Level Success
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-TestUsers'
    'Remove-TestUsers'
)
