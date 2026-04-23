#Requires -Version 7.0

<#
.SYNOPSIS
    Pre-provision OneDrive for Business personal sites for lab test users.

.DESCRIPTION
    OneDrive personal sites are lazy-provisioned on a user's first sign-in.
    Until then, Graph /users/{upn}/drive returns 404 and the deployer's
    TestData.psm1 cannot upload documents or assign sensitivity labels via
    /drives/{id}/items/{id}/assignSensitivityLabel.

    Strategy: call the SharePoint admin REST endpoint
    /_api/SPO.UserProfileService/CreatePersonalSiteEnqueueBulk directly —
    the same endpoint that Request-SPOPersonalSite wraps. This avoids the
    Microsoft.Online.SharePoint.PowerShell module which has null-ref issues
    on Connect-SPOService under PS7 / macOS.

    Uses Az.Accounts for acquiring the SharePoint admin access token (the
    SPO REST endpoint won't accept Graph tokens). After enqueueing, polls
    Graph /users/{upn}/drive until the drive materializes (server-side timer
    job, typically 5-15 min).

.PARAMETER ConfigPath
    Path to the lab config JSON. Reads workloads.testUsers.users[].upn.

.PARAMETER LabProfile
    Profile shorthand (e.g. ai). Resolves to configs/<cloud>/<profile>-demo.json.

.PARAMETER Cloud
    commercial | gcc. Default: commercial.

.PARAMETER TenantId
    Optional tenant ID for Az sign-in (uses existing context if omitted).

.PARAMETER Wait
    Poll Graph for drive readiness after enqueue (max 20 min).

.EXAMPLE
    ./scripts/Request-OneDriveProvisioning.ps1 -LabProfile ai -Wait
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$LabProfile,

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = 'commercial',

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [switch]$Wait
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules' 'Logging.psm1') -Force

function Resolve-LabConfigPath {
    param([string]$ExplicitConfigPath, [string]$ProfileName, [string]$CloudEnv)
    if ($ExplicitConfigPath) {
        if (-not (Test-Path $ExplicitConfigPath)) { throw "Config file not found: $ExplicitConfigPath" }
        return (Resolve-Path $ExplicitConfigPath).Path
    }
    if (-not $ProfileName) { throw 'Provide -ConfigPath or -LabProfile.' }
    $candidate = Join-Path $repoRoot 'configs' $CloudEnv "$ProfileName-demo.json"
    if (-not (Test-Path $candidate)) { throw "Config not found: $candidate" }
    return (Resolve-Path $candidate).Path
}

function Get-SpoAdminUrl {
    param([string]$TenantDomain)
    # contoso.onmicrosoft.com -> https://contoso-admin.sharepoint.com
    $tenantSlug = $TenantDomain.Split('.')[0]
    return "https://$tenantSlug-admin.sharepoint.com"
}

function Connect-AzIfNeeded {
    param([string]$Tenant)
    if (-not (Get-Command Connect-AzAccount -ErrorAction SilentlyContinue)) {
        Import-Module Az.Accounts -ErrorAction Stop
    }
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if ($ctx -and (-not $Tenant -or $ctx.Tenant.Id -eq $Tenant)) {
        Write-LabLog -Message "Reusing Az session ($($ctx.Account.Id))." -Level Info
        return
    }
    $params = @{ ErrorAction = 'Stop' }
    if ($Tenant) { $params['TenantId'] = $Tenant }
    Connect-AzAccount @params | Out-Null
    Write-LabLog -Message 'Connected to Azure.' -Level Success
}

function Connect-GraphIfNeeded {
    param([string]$Tenant)
    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    }
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx -and $ctx.Scopes -contains 'User.Read.All' -and ($ctx.Scopes -contains 'Sites.ReadWrite.All' -or $ctx.Scopes -contains 'Files.ReadWrite.All')) {
        return
    }
    $params = @{
        Scopes      = @('User.Read.All', 'Sites.ReadWrite.All')
        NoWelcome   = $true
        ErrorAction = 'Stop'
    }
    if ($Tenant) { $params['TenantId'] = $Tenant }
    Connect-MgGraph @params | Out-Null
}

function Get-SpoAccessToken {
    param([string]$SpoAdminUrl)
    # Az returns SecureString in newer versions; convert explicitly.
    $token = Get-AzAccessToken -ResourceUrl $SpoAdminUrl -AsSecureString -ErrorAction Stop
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token.Token)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Invoke-CreatePersonalSiteEnqueueBulk {
    param(
        [Parameter(Mandatory)][string]$SpoAdminUrl,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string[]]$Upns
    )
    $uri = "$SpoAdminUrl/_api/SPO.UserProfileService/CreatePersonalSiteEnqueueBulk"
    $body = @{ emailIDs = $Upns } | ConvertTo-Json -Compress
    $headers = @{
        Authorization    = "Bearer $AccessToken"
        Accept           = 'application/json;odata=verbose'
        'Content-Type'   = 'application/json;odata=verbose'
        'X-RequestDigest' = 'unused'
    }
    Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body -ErrorAction Stop | Out-Null
}

function Get-UserDriveState {
    param([Parameter(Mandatory)][string]$Upn)
    try {
        $drive = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/users/$Upn/drive" -ErrorAction Stop
        if ($drive -and $drive.id) { return @{ State = 'Provisioned'; DriveId = [string]$drive.id } }
        return @{ State = 'Pending'; DriveId = $null }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match '404|NotFound|ResourceNotFound|mysite') { return @{ State = 'Pending'; DriveId = $null } }
        return @{ State = "Error: $msg"; DriveId = $null }
    }
}

# --- Main ---

$resolvedPath = Resolve-LabConfigPath -ExplicitConfigPath $ConfigPath -ProfileName $LabProfile -CloudEnv $Cloud
Write-LabLog -Message "Loading config: $resolvedPath" -Level Info
$config = Get-Content $resolvedPath -Raw | ConvertFrom-Json

$upns = @()
foreach ($u in @($config.workloads.testUsers.users)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$u.upn)) { $upns += [string]$u.upn }
}
if ($upns.Count -eq 0) { throw 'Config has no test users defined.' }

$tenantDomain = [string]$config.domain
if ([string]::IsNullOrWhiteSpace($tenantDomain)) { throw 'Config missing "domain" field (e.g. contoso.onmicrosoft.com).' }
$spoAdminUrl = Get-SpoAdminUrl -TenantDomain $tenantDomain
Write-LabLog -Message "SharePoint admin endpoint: $spoAdminUrl" -Level Info

# Pre-check: skip already-provisioned users to make re-runs idempotent.
Connect-GraphIfNeeded -Tenant $TenantId

$toEnqueue = @()
$preProvisioned = @()
foreach ($upn in $upns) {
    $state = Get-UserDriveState -Upn $upn
    if ($state.State -eq 'Provisioned') {
        $preProvisioned += $upn
        Write-LabLog -Message "Already provisioned: $upn" -Level Success
    } else {
        $toEnqueue += $upn
    }
}

if ($toEnqueue.Count -gt 0) {
    Connect-AzIfNeeded -Tenant $TenantId
    Write-LabLog -Message 'Acquiring SharePoint admin access token.' -Level Info
    $spoToken = Get-SpoAccessToken -SpoAdminUrl $spoAdminUrl

    Write-LabLog -Message "Enqueuing $($toEnqueue.Count) user(s) for personal site creation." -Level Info
    try {
        Invoke-CreatePersonalSiteEnqueueBulk -SpoAdminUrl $spoAdminUrl -AccessToken $spoToken -Upns $toEnqueue
        Write-LabLog -Message 'Personal site creation enqueued. Server-side timer job creates the sites (typically 5-15 min).' -Level Success
    } catch {
        throw "CreatePersonalSiteEnqueueBulk failed: $($_.Exception.Message)"
    }
}

$results = foreach ($upn in $upns) {
    $state = Get-UserDriveState -Upn $upn
    [pscustomobject]@{ Upn = $upn; State = $state.State; DriveId = $state.DriveId }
}

if ($Wait -and ($results | Where-Object { $_.State -eq 'Pending' })) {
    $deadline = (Get-Date).AddMinutes(20)
    Write-LabLog -Message 'Polling for drive readiness (timeout 20 min)…' -Level Info
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 60
        $results = foreach ($upn in $upns) {
            $state = Get-UserDriveState -Upn $upn
            [pscustomobject]@{ Upn = $upn; State = $state.State; DriveId = $state.DriveId }
        }
        $pending = @($results | Where-Object { $_.State -eq 'Pending' })
        Write-LabLog -Message "  Pending: $($pending.Count) / $($results.Count)" -Level Info
        if ($pending.Count -eq 0) { break }
    }
}

Write-Host ''
Write-Host '=== OneDrive Provisioning Summary ===' -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-String | Write-Host

$pending = @($results | Where-Object { $_.State -eq 'Pending' })
$ready = @($results | Where-Object { $_.State -eq 'Provisioned' })
$errors = @($results | Where-Object { $_.State -like 'Error*' })

Write-Host "Provisioned: $($ready.Count)"
Write-Host "Pending: $($pending.Count)"
if ($errors.Count -gt 0) { Write-Host "Errors: $($errors.Count)" -ForegroundColor Yellow }

if ($pending.Count -gt 0) {
    Write-Host ''
    Write-Host 'Next step: wait 5-15 minutes then rerun Deploy-Lab.ps1 (or rerun this script with -Wait to poll).' -ForegroundColor Yellow
}

if ($errors.Count -gt 0) { exit 2 }
if ($pending.Count -gt 0) { exit 1 }
exit 0
