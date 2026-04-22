#Requires -Version 7.0

<#
.SYNOPSIS
    Conditional Access workload module for purview-lab-deployer.
    Uses Microsoft Graph cmdlets (New/Get/Remove-MgIdentityConditionalAccessPolicy)
    from the Microsoft.Graph.Identity.SignIns module.
#>

function Deploy-ConditionalAccess {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $createdPolicies = [System.Collections.Generic.List[hashtable]]::new()

    # Validate Graph scopes before attempting CA policy operations
    $context = Get-MgContext -ErrorAction SilentlyContinue
    $grantedScopes = @($context.Scopes)
    $requiredScopes = @('Policy.ReadWrite.ConditionalAccess', 'Policy.Read.All')
    $missingScopes = @($requiredScopes | Where-Object { $_ -notin $grantedScopes })
    if ($missingScopes.Count -gt 0) {
        Write-LabLog -Message "Conditional Access requires Graph scopes not in current token: $($missingScopes -join ', '). Disconnect and reconnect with: Connect-MgGraph -Scopes 'Policy.ReadWrite.ConditionalAccess','Policy.Read.All','Application.Read.All'" -Level Warning
        Write-LabLog -Message "Skipping all Conditional Access policies due to missing scopes." -Level Warning
        return @{ policies = @() }
    }

    foreach ($policy in $Config.workloads.conditionalAccess.policies) {
        $name = "$($Config.prefix)-$($policy.name)"

        try {
            $existing = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$name'" -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($existing) {
                Write-LabLog -Message "Conditional Access policy already exists: $name" -Level Info
                $createdPolicies.Add(@{
                    name   = $name
                    id     = $existing.Id
                    status = 'existing'
                })
                continue
            }

            # Build conditions. Conditional Access always requires
            # applications.includeApplications to be non-empty — Microsoft Graph
            # rejects the policy otherwise with:
            #   1011: 'applications' condition must specify the applications to include.
            #   Try 'includeApplications' = ['none'] to start with.
            # Use 'none' when config omits target app IDs so the policy deploys
            # as a scaffold that the operator can point at real enterprise apps
            # post-deploy.
            $targetApps = @($policy.targetAppIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($targetApps.Count -eq 0) { $targetApps = @('none') }

            $conditions = @{
                Applications = @{ IncludeApplications = $targetApps }
                Users        = @{ IncludeUsers = @('All') }
            }

            # Support excludeAppIds
            if ($policy.PSObject.Properties['excludeAppIds'] -and $policy.excludeAppIds) {
                $conditions.Applications['ExcludeApplications'] = @($policy.excludeAppIds)
            }

            if ($policy.PSObject.Properties['signInRiskLevels'] -and $policy.signInRiskLevels) {
                $conditions['SignInRiskLevels'] = @($policy.signInRiskLevels)
            }

            # Build grant controls. Accept either legacy shorthand
            # ({ action: "block" }) or the Graph-native nested shape
            # ({ grantControls: { builtInControls: ["block"] } }).
            $grantControls = @{
                Operator = 'OR'
            }

            $builtIns = @()
            if ($policy.PSObject.Properties['grantControls'] -and
                $policy.grantControls -and
                $policy.grantControls.PSObject.Properties['builtInControls']) {
                $builtIns = @($policy.grantControls.builtInControls |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            }
            elseif ($policy.PSObject.Properties['action']) {
                switch ([string]$policy.action) {
                    'block'           { $builtIns = @('block') }
                    'mfa'             { $builtIns = @('mfa') }
                    'compliantDevice' { $builtIns = @('compliantDevice') }
                }
            }

            if ($builtIns.Count -eq 0) {
                # Graph requires at least one control. Default to block for
                # policies that don't specify — safer than silently shipping
                # a policy with no effect.
                $builtIns = @('block')
                Write-LabLog -Message "Conditional Access policy '$name' has no grant controls specified; defaulting to 'block'." -Level Warning
            }
            $grantControls['BuiltInControls'] = $builtIns

            # Use report-only mode for lab safety
            $state = if ($policy.PSObject.Properties['state'] -and $policy.state) {
                $policy.state
            } else {
                'enabledForReportingButNotEnforced'
            }

            $bodyParams = @{
                DisplayName   = $name
                State         = $state
                Conditions    = $conditions
                GrantControls = $grantControls
            }

            if ($PSCmdlet.ShouldProcess($name, "Create Conditional Access policy (action: $($policy.action))")) {
                $created = New-MgIdentityConditionalAccessPolicy -BodyParameter $bodyParams -ErrorAction Stop

                Write-LabLog -Message "Created Conditional Access policy: $name (state: $state)" -Level Success
                $createdPolicies.Add(@{
                    name   = $name
                    id     = $created.Id
                    action = $policy.action
                    state  = $state
                    status = 'created'
                })
            }
        }
        catch {
            Write-LabLog -Message "Error creating Conditional Access policy ${name}: $($_.Exception.Message)" -Level Warning
        }
    }

    return @{
        policies = $createdPolicies.ToArray()
    }
}

function Remove-ConditionalAccess {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    $targetPolicies = @()

    # Prefer manifest-based removal
    if ($Manifest) {
        foreach ($manifestPolicy in @($Manifest.policies)) {
            if ($manifestPolicy.id) {
                $targetPolicies += @{ name = [string]$manifestPolicy.name; id = [string]$manifestPolicy.id }
            }
            elseif ($manifestPolicy.name) {
                $targetPolicies += @{ name = [string]$manifestPolicy.name; id = $null }
            }
        }
    }

    # Fallback to config-based removal
    if ($targetPolicies.Count -eq 0) {
        foreach ($policy in $Config.workloads.conditionalAccess.policies) {
            $targetPolicies += @{ name = "$($Config.prefix)-$($policy.name)"; id = $null }
        }
    }

    foreach ($target in $targetPolicies) {
        $name = $target.name

        try {
            # Find by ID first, then by name
            $existing = $null
            if ($target.id) {
                $existing = Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $target.id -ErrorAction SilentlyContinue
            }
            if (-not $existing) {
                $existing = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$name'" -ErrorAction SilentlyContinue |
                    Select-Object -First 1
            }

            if (-not $existing) {
                Write-LabLog -Message "Conditional Access policy not found, skipping: $name" -Level Warning
                continue
            }

            if ($PSCmdlet.ShouldProcess($name, 'Remove Conditional Access policy')) {
                Remove-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existing.Id -ErrorAction Stop
                Write-LabLog -Message "Removed Conditional Access policy: $name" -Level Success
            }
        }
        catch {
            Write-LabLog -Message "Error removing Conditional Access policy ${name}: $($_.Exception.Message)" -Level Warning
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-ConditionalAccess'
    'Remove-ConditionalAccess'
)
