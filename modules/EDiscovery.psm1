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

        Write-LabLog -Message "Processing eDiscovery case: $name" -Level Info

        # --- Case ---
        $existing = $null
        try {
            $existing = Get-ComplianceCase -Identity $name -ErrorAction SilentlyContinue
        }
        catch {
            # Case does not exist
        }

        if (-not $existing) {
            if ($PSCmdlet.ShouldProcess($name, 'New-ComplianceCase')) {
                Write-LabLog -Message "Creating compliance case: $name" -Level Info
                New-ComplianceCase -Name $name -Description $case.description | Out-Null
            }
        }
        else {
            Write-LabLog -Message "Compliance case already exists: $name" -Level Info
        }

        # --- Custodians as case members ---
        foreach ($upn in $case.custodians) {
            if ($PSCmdlet.ShouldProcess("$upn -> $name", 'Add-ComplianceCaseMember')) {
                Write-LabLog -Message "Adding case member: $upn to $name" -Level Info
                try {
                    Add-ComplianceCaseMember -Case $name -Member $upn -ErrorAction SilentlyContinue
                }
                catch {
                    Write-LabLog -Message "Could not add member $upn to case $name`: $_" -Level Warning
                }
            }
        }

        # --- Hold policy ---
        $existingHold = $null
        try {
            $existingHold = Get-CaseHoldPolicy -Case $name -Identity $holdName -ErrorAction SilentlyContinue
        }
        catch {
            # Hold does not exist
        }

        if (-not $existingHold) {
            if ($PSCmdlet.ShouldProcess($holdName, 'New-CaseHoldPolicy')) {
                Write-LabLog -Message "Creating case hold policy: $holdName" -Level Info
                New-CaseHoldPolicy -Name $holdName -Case $name -ExchangeLocation $case.custodians | Out-Null

                # Hold rule
                $holdRuleName = "$holdName-Rule"
                Write-LabLog -Message "Creating case hold rule: $holdRuleName" -Level Info
                New-CaseHoldRule -Name $holdRuleName -Policy $holdName -ContentMatchQuery $case.holdQuery | Out-Null
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
            # Search does not exist
        }

        if (-not $existingSearch) {
            if ($PSCmdlet.ShouldProcess($searchName, 'New-ComplianceSearch')) {
                Write-LabLog -Message "Creating compliance search: $searchName" -Level Info
                New-ComplianceSearch -Name $searchName -Case $name -ExchangeLocation $case.custodians -ContentMatchQuery $case.searchQuery | Out-Null
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
            custodians = $case.custodians
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
        [PSCustomObject]$Manifest
    )

    $cases = $Config.workloads.eDiscovery.cases
    # Process in reverse order for clean teardown
    [array]::Reverse($cases)

    foreach ($case in $cases) {
        $name = "$($Config.prefix)-$($case.name)"
        $holdName = "$name-Hold"
        $holdRuleName = "$holdName-Rule"
        $searchName = "$name-Search"

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
