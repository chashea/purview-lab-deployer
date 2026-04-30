#Requires -Version 7.0

function Deploy-AuditConfig {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $results = @{
        auditEnabled    = $false
        searches        = @()
        exoConnected    = $false
    }

    # Get-AdminAuditLogConfig / Set-AdminAuditLogConfig / Search-UnifiedAuditLog live in
    # Exchange Online PowerShell, not the Security & Compliance (IPPS) session that the
    # deployer connects to by default. Without an EXO connection these cmdlets are
    # unrecognized and unified audit log ingestion is never enabled — which causes
    # Activity Explorer to stay empty in fresh tenants. Open a transient EXO session
    # for the duration of this module if the cmdlet is missing.
    $exoConnectedHere = $false
    if (-not (Get-Command Get-AdminAuditLogConfig -ErrorAction SilentlyContinue)) {
        try {
            if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
                throw "ExchangeOnlineManagement module is not installed."
            }
            Import-Module ExchangeOnlineManagement -ErrorAction Stop

            $exoParams = @{
                ShowBanner  = $false
                ErrorAction = 'Stop'
            }
            $cloud = if ($Config.PSObject.Properties['cloud']) { ([string]$Config.cloud).ToLowerInvariant() } else { 'commercial' }
            # GCC Moderate uses the default O365Default environment — no override needed.
            # GCC High and DoD require explicit ExchangeEnvironmentName.
            switch ($cloud) {
                'gcchigh' { $exoParams['ExchangeEnvironmentName'] = 'O365USGovGCCHigh' }
                'dod'     { $exoParams['ExchangeEnvironmentName'] = 'O365USGovDoD' }
            }
            if ($env:PURVIEW_LAB_UPN) {
                $exoParams['UserPrincipalName'] = $env:PURVIEW_LAB_UPN
            }
            Connect-ExchangeOnline @exoParams
            Write-LabLog -Message "Opened transient Exchange Online session for audit configuration ($cloud)." -Level Info
            $exoConnectedHere = $true
            $results.exoConnected = $true
        }
        catch {
            Write-LabLog -Message "Could not open Exchange Online session for audit configuration: $($_.Exception.Message). Skipping unified audit log enablement — enable manually with Connect-ExchangeOnline + Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled `$true." -Level Warning
            return $results
        }
    }

    try {
        # Enable unified audit logging if not already enabled
        try {
            $auditConfig = Get-AdminAuditLogConfig -ErrorAction Stop
            if ($auditConfig.UnifiedAuditLogIngestionEnabled) {
                Write-LabLog -Message 'Unified audit logging is already enabled.' -Level Info
                $results.auditEnabled = $true
            }
            else {
                if ($PSCmdlet.ShouldProcess('Unified Audit Log', 'Enable')) {
                    Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true -ErrorAction Stop
                    Write-LabLog -Message 'Enabled unified audit logging.' -Level Success
                    $results.auditEnabled = $true
                }
            }
        }
        catch {
            Write-LabLog -Message "Could not configure audit logging: $($_.Exception.Message)" -Level Warning
        }

        # Create saved audit log searches for AI activities
        if ($Config.workloads.PSObject.Properties['auditConfig'] -and $Config.workloads.auditConfig.searches) {
            foreach ($search in $Config.workloads.auditConfig.searches) {
                $searchName = "$($Config.prefix)-$($search.name)"

                if ($PSCmdlet.ShouldProcess($searchName, 'Create audit log search')) {
                    try {
                        $searchParams = @{
                            Name       = $searchName
                            Operations = $search.operations
                            StartDate  = (Get-Date).AddDays(-30)
                            EndDate    = (Get-Date).AddDays(1)
                        }

                        $searchResult = Search-UnifiedAuditLog @searchParams -ResultSize 1 -ErrorAction Stop
                        $resultCount = if ($searchResult) { ($searchResult | Measure-Object).Count } else { 0 }

                        Write-LabLog -Message "Audit search '$searchName' validated ($resultCount recent records found)." -Level Success
                        $results.searches += @{
                            name       = $searchName
                            operations = $search.operations
                            status     = 'validated'
                        }
                    }
                    catch {
                        Write-LabLog -Message "Audit search '$searchName' could not be validated: $($_.Exception.Message)" -Level Warning
                        $results.searches += @{
                            name   = $searchName
                            status = 'failed'
                        }
                    }
                }
            }
        }
    }
    finally {
        if ($exoConnectedHere) {
            try {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
                Write-LabLog -Message 'Closed transient Exchange Online session.' -Level Info
            }
            catch {
                Write-Verbose "Disconnect-ExchangeOnline failed (non-fatal): $($_.Exception.Message)"
            }
        }
    }

    return $results
}

function Remove-AuditConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    # Audit config is non-destructive — we don’t disable audit logging on removal
    # Saved searches are transient (Search-UnifiedAuditLog doesn’t persist)
    if ($PSCmdlet.ShouldProcess($Config.prefix, 'Preserve audit configuration')) {
        $searchCount = if ($Manifest -and $Manifest.PSObject.Properties['searches']) { @($Manifest.searches).Count } else { 0 }
        Write-LabLog -Message "Audit configuration is preserved on removal (audit logging remains enabled). Manifest search entries: $searchCount." -Level Info
    }
}

Export-ModuleMember -Function @(
    'Deploy-AuditConfig'
    'Remove-AuditConfig'
)
