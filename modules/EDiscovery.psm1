#Requires -Version 7.0

<#
.SYNOPSIS
    eDiscovery workload module for purview-lab-deployer.
#>

function Deploy-EDiscovery {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $cases = $Config.workloads.eDiscovery.cases
    $manifestCases = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($case in $cases) {
        $name = "$($Config.prefix)-$($case.name)"
        $holdName = "$name-Hold"
        $searchName = "$name-Search"
        $resolvedCustodians = [System.Collections.Generic.List[string]]::new()
        $missingCustodians = [System.Collections.Generic.List[string]]::new()

        Write-LabLog -Message "Processing eDiscovery case: $name" -Level Info

        foreach ($custodianIdentity in $case.custodians) {
            $resolvedUser = Get-LabUserByIdentity -Identity $custodianIdentity -DefaultDomain $Config.domain
            if ($resolvedUser -and -not [string]::IsNullOrWhiteSpace([string]$resolvedUser.UserPrincipalName)) {
                $resolvedCustodians.Add([string]$resolvedUser.UserPrincipalName)
            }
            else {
                $missingCustodians.Add([string]$custodianIdentity)
            }
        }

        if ($missingCustodians.Count -gt 0) {
            $missingSummary = (($missingCustodians | Sort-Object -Unique) -join ', ')
            if ($resolvedCustodians.Count -eq 0) {
                $ctx = Get-MgContext
                if ($ctx -and -not [string]::IsNullOrWhiteSpace($ctx.Account)) {
                    Write-LabLog -Message "eDiscovery case '$name': configured custodians not found ($missingSummary). Falling back to current user: $($ctx.Account)" -Level Warning
                    $resolvedCustodians.Add([string]$ctx.Account)
                }
                else {
                    throw "eDiscovery case '$name' references custodians that were not found in Microsoft Graph: $missingSummary"
                }
            }
            else {
                Write-LabLog -Message "eDiscovery case '$name': some custodians not found ($missingSummary). Proceeding with resolved custodians." -Level Warning
            }
        }

        $resolvedCustodianAddresses = @($resolvedCustodians | Sort-Object -Unique)
        $exchangeReadyCustodians = [System.Collections.Generic.List[string]]::new()
        $nonExchangeCustodians = [System.Collections.Generic.List[string]]::new()

        foreach ($upn in $resolvedCustodianAddresses) {
            $recipient = $null
            try {
                $recipient = Get-Recipient -Identity $upn -ErrorAction Stop
            }
            catch {
                $recipient = $null
            }

            if ($recipient) {
                $exchangeReadyCustodians.Add($upn)
            }
            else {
                $nonExchangeCustodians.Add($upn)
            }
        }

        if ($nonExchangeCustodians.Count -gt 0) {
            $nonExchangeSummary = (($nonExchangeCustodians | Sort-Object -Unique) -join ', ')
            Write-LabLog -Message "Skipping non-mailbox custodians for eDiscovery case '$name': $nonExchangeSummary" -Level Warning
        }

        $targetCustodians = @($exchangeReadyCustodians | Sort-Object -Unique)
        if ($targetCustodians.Count -eq 0) {
            Write-LabLog -Message "No mailbox-enabled custodians are available for eDiscovery case '$name'. Case will be created without hold/search locations." -Level Warning
        }

        # --- Case ---
        $existing = $null
        try {
            $existing = Get-ComplianceCase -Identity $name -ErrorAction SilentlyContinue
        }
        catch {
            $null = $_ # Case does not exist
        }

        if (-not $existing) {
            if ($PSCmdlet.ShouldProcess($name, 'New-ComplianceCase')) {
                Write-LabLog -Message "Creating compliance case: $name" -Level Info
                New-ComplianceCase -Name $name -Description $case.description -ErrorAction Stop | Out-Null
            }
        }
        else {
            Write-LabLog -Message "Compliance case already exists: $name" -Level Info
        }

        # --- Custodians as case members ---
        if ($targetCustodians.Count -gt 0) {
            foreach ($upn in $targetCustodians) {
                if ($PSCmdlet.ShouldProcess("$upn -> $name", 'Add-ComplianceCaseMember')) {
                    Write-LabLog -Message "Adding case member: $upn to $name" -Level Info
                    try {
                        Add-ComplianceCaseMember -Case $name -Member $upn -ErrorAction Stop -WarningAction SilentlyContinue
                    }
                    catch {
                        Write-LabLog -Message "Could not add member $upn to case $name`: $($_.Exception.Message)" -Level Warning
                    }
                }
            }
        }

        # --- Hold policy ---
        $existingHold = $null
        try {
            $existingHold = Get-CaseHoldPolicy -Case $name -Identity $holdName -ErrorAction SilentlyContinue
        }
        catch {
            $null = $_ # Hold does not exist
        }

        if (-not $existingHold) {
            if ($targetCustodians.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess($holdName, 'New-CaseHoldPolicy')) {
                    try {
                        Write-LabLog -Message "Creating case hold policy: $holdName" -Level Info
                        New-CaseHoldPolicy -Name $holdName -Case $name -ExchangeLocation $targetCustodians -ErrorAction Stop | Out-Null

                        # Hold rule
                        $holdRuleName = "$holdName-Rule"
                        Write-LabLog -Message "Creating case hold rule: $holdRuleName" -Level Info
                        New-CaseHoldRule -Name $holdRuleName -Policy $holdName -ContentMatchQuery $case.holdQuery -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-LabLog -Message "Could not create hold artifacts for case $name`: $($_.Exception.Message)" -Level Warning
                    }
                }
            }
            else {
                Write-LabLog -Message "Skipping hold creation for case $name because no mailbox-enabled custodians were resolved." -Level Warning
            }
        }
        else {
            Write-LabLog -Message "Case hold policy already exists: $holdName" -Level Info
        }

        # --- Compliance search ---
        $existingSearch = $null
        try {
            $existingSearch = Get-ComplianceSearch -Identity $searchName -ErrorAction SilentlyContinue
        }
        catch {
            $null = $_ # Search does not exist
        }

        if (-not $existingSearch) {
            if ($targetCustodians.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess($searchName, 'New-ComplianceSearch')) {
                    try {
                        Write-LabLog -Message "Creating compliance search: $searchName" -Level Info
                        New-ComplianceSearch -Name $searchName -Case $name -ExchangeLocation $targetCustodians -ContentMatchQuery $case.searchQuery -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-LabLog -Message "Could not create compliance search $searchName`: $($_.Exception.Message)" -Level Warning
                    }
                }
            }
            else {
                Write-LabLog -Message "Skipping compliance search creation for case $name because no mailbox-enabled custodians were resolved." -Level Warning
            }
        }
        else {
            Write-LabLog -Message "Compliance search already exists: $searchName" -Level Info
        }

        $manifestCases.Add([PSCustomObject]@{
            caseName   = $name
            holdName   = $holdName
            holdRule   = "$holdName-Rule"
            searchName = $searchName
            custodians = $targetCustodians
        })
    }

    return [PSCustomObject]@{
        cases = $manifestCases.ToArray()
    }
}

function Remove-EDiscovery {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest  # Reserved for manifest-based removal
    )

    $targetCases = @()

    if ($Manifest) {
        foreach ($manifestCase in @($Manifest.cases)) {
            if ($manifestCase.caseName) {
                $targetCases += [PSCustomObject]@{
                    caseName   = [string]$manifestCase.caseName
                    holdName   = [string]$manifestCase.holdName
                    holdRule   = [string]$manifestCase.holdRule
                    searchName = [string]$manifestCase.searchName
                }
            }
        }
    }

    if ($targetCases.Count -eq 0) {
        foreach ($case in $Config.workloads.eDiscovery.cases) {
            $name = "$($Config.prefix)-$($case.name)"
            $holdName = "$name-Hold"
            $targetCases += [PSCustomObject]@{
                caseName   = $name
                holdName   = $holdName
                holdRule   = "$holdName-Rule"
                searchName = "$name-Search"
            }
        }
    }

    # Process in reverse order for clean teardown
    [array]::Reverse($targetCases)

    foreach ($case in $targetCases) {
        $name = $case.caseName
        $holdName = $case.holdName
        $holdRuleName = $case.holdRule
        $searchName = $case.searchName

        Write-LabLog -Message "Removing eDiscovery resources for case: $name" -Level Info

        # --- Remove searches ---
        try {
            $search = Get-ComplianceSearch -Identity $searchName -ErrorAction SilentlyContinue
            if ($search) {
                if ($PSCmdlet.ShouldProcess($searchName, 'Remove-ComplianceSearch')) {
                    Write-LabLog -Message "Removing compliance search: $searchName" -Level Info
                    Remove-ComplianceSearch -Identity $searchName -Confirm:$false | Out-Null
                }
            }
        }
        catch {
            Write-LabLog -Message "Compliance search not found or already removed: $searchName" -Level Warning
        }

        # --- Remove hold rule ---
        try {
            $rule = Get-CaseHoldRule -Policy $holdName -ErrorAction SilentlyContinue
            if ($rule) {
                if ($PSCmdlet.ShouldProcess($holdRuleName, 'Remove-CaseHoldRule')) {
                    Write-LabLog -Message "Removing case hold rule: $holdRuleName" -Level Info
                    Remove-CaseHoldRule -Identity $holdRuleName -Confirm:$false | Out-Null
                }
            }
        }
        catch {
            Write-LabLog -Message "Case hold rule not found or already removed: $holdRuleName" -Level Warning
        }

        # --- Remove hold policy ---
        try {
            $hold = Get-CaseHoldPolicy -Case $name -Identity $holdName -ErrorAction SilentlyContinue
            if ($hold) {
                if ($PSCmdlet.ShouldProcess($holdName, 'Remove-CaseHoldPolicy')) {
                    Write-LabLog -Message "Removing case hold policy: $holdName" -Level Info
                    Remove-CaseHoldPolicy -Identity $holdName -Confirm:$false | Out-Null
                }
            }
        }
        catch {
            Write-LabLog -Message "Case hold policy not found or already removed: $holdName" -Level Warning
        }

        # --- Remove case ---
        try {
            $existing = Get-ComplianceCase -Identity $name -ErrorAction SilentlyContinue
            if ($existing) {
                if ($PSCmdlet.ShouldProcess($name, 'Remove-ComplianceCase')) {
                    Write-LabLog -Message "Removing compliance case: $name" -Level Info
                    Remove-ComplianceCase -Identity $name -Confirm:$false | Out-Null
                }
            }
        }
        catch {
            Write-LabLog -Message "Compliance case not found or already removed: $name" -Level Warning
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-EDiscovery'
    'Remove-EDiscovery'
)
