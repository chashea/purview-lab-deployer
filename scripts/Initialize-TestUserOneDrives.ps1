#Requires -Version 7.0
<#
.SYNOPSIS
Pre-provisions OneDrive personal sites for the lab's test users so the smoke
test can upload .docx files to each user's own drive (not the admin's).

.DESCRIPTION
Microsoft Graph's /users/{upn}/drive endpoint returns 404 NotFound for any
user whose personal OneDrive site has never been provisioned. The smoke test
falls back to /me/drive (the signed-in admin) when that happens, which
distorts the per-user DLP signal in Activity Explorer.

IMPORTANT — KNOWN LIMITATIONS (read before running)
====================================================
A. Licensing alone does NOT auto-provision OneDrive. The user must either:
     1) Sign in to https://portal.office.com once, OR
     2) An admin must trigger provisioning (this script, or SPO Admin Center
        > More features > User profiles > Set up OneDrive).

B. Even AFTER provisioning, the Invoke-SmokeTest.ps1 script today uses
   delegated Microsoft Graph auth as the signed-in admin. That delegated
   token CANNOT write to other users' OneDrives — Graph returns 403/404 on
   PUT to /users/{otherUpn}/drive/.... Cross-user upload requires APPLICATION
   permission (Files.ReadWrite.All app-only), which means registering an
   Entra app + storing a cert/secret + tenant admin consent. Without that,
   even a successfully-provisioned per-user OneDrive will not receive files
   from this smoke test.

So this script alone is necessary but not sufficient for per-user signal.
For demo purposes, the simplest workable path is:
   - Have each test user sign into portal.office.com once (provisions their
     OneDrive AND lets them be a real DLP-signal owner if they upload).
   - OR accept that all smoke-test files land in the admin's drive (still
     triggers the rules; signal attributed to admin in Activity Explorer).

.PARAMETER LabProfile
Lab profile name (basic, financial, healthcare, etc.). Used to look up
configs/<cloud>/<profile>-demo.json.

.PARAMETER ConfigPath
Explicit config file path. Overrides -LabProfile.

.PARAMETER Cloud
Azure cloud (commercial, gcc, gcchigh, dod). Default: commercial.

.PARAMETER UseSpoPowerShell
Use Request-(PnP|SPO)PersonalSite to provision OneDrives in bulk. Requires
either the PnP.PowerShell module + a registered Entra app (-PnPClientId)
or Microsoft.Online.SharePoint.PowerShell on Windows + SharePoint Admin role.

.PARAMETER SpoAdminUrl
Required when -UseSpoPowerShell is set. e.g. https://contoso-admin.sharepoint.com

.PARAMETER PnPClientId
Entra app id for PnP.PowerShell. Required as of Sep 2024 since the built-in
PnP Management Shell app (-Interactive) was deprecated. Register an app with
Sites.FullControl.All (App) granted by tenant admin, then pass its appId here.

.EXAMPLE
# Best-effort: just poke Graph (rarely succeeds — see KNOWN LIMITATIONS)
./scripts/Initialize-TestUserOneDrives.ps1 -LabProfile basic -Cloud gcc

.EXAMPLE
# Reliable: PnP with a tenant-registered Entra app
./scripts/Initialize-TestUserOneDrives.ps1 -LabProfile basic -Cloud gcc `
  -UseSpoPowerShell -SpoAdminUrl https://mngenvmcap659995-admin.sharepoint.com `
  -PnPClientId 00000000-0000-0000-0000-000000000000
#>

[CmdletBinding(DefaultParameterSetName = 'Profile', SupportsShouldProcess)]
param(
    [Parameter(ParameterSetName = 'Profile', Mandatory)]
    [string]$LabProfile,

    [Parameter(ParameterSetName = 'Path', Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [ValidateSet('commercial', 'gcc', 'gcchigh', 'dod')]
    [string]$Cloud = 'commercial',

    [switch]$UseSpoPowerShell,

    [string]$SpoAdminUrl,

    [string]$PnPClientId
)

$ErrorActionPreference = 'Stop'

if ($UseSpoPowerShell -and -not $SpoAdminUrl) {
    throw '-SpoAdminUrl is required when -UseSpoPowerShell is set.'
}

# --- Resolve config path ---
if ($PSCmdlet.ParameterSetName -eq 'Profile') {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $ConfigPath = Join-Path $repoRoot "configs/$Cloud/$LabProfile-demo.json"
    if (-not (Test-Path $ConfigPath)) {
        throw "Config not found: $ConfigPath"
    }
}

Write-Host "Loading config: $ConfigPath" -ForegroundColor Cyan
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -Depth 20

# --- Extract unique test user UPNs ---
$users = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Schema: workloads.testUsers.users[].upn (current), with legacy fallback to .users[]
$candidateUserLists = @()
if ($config.workloads.testUsers.users) { $candidateUserLists += , @($config.workloads.testUsers.users) }
if ($config.users) { $candidateUserLists += , @($config.users) }

foreach ($list in $candidateUserLists) {
    foreach ($u in $list) {
        if ($u.upn) { [void]$users.Add($u.upn) }
    }
}

if ($users.Count -eq 0) {
    throw 'No users found in workloads.testUsers.users[].upn (or legacy users[].upn)'
}

Write-Host "Found $($users.Count) test user(s)" -ForegroundColor Cyan

# --- Path A: SPO PowerShell (preferred) ---
if ($UseSpoPowerShell) {
    # Prefer cross-platform PnP.PowerShell on macOS/Linux/PS7;
    # fall back to legacy Microsoft.Online.SharePoint.PowerShell on Windows.
    $pnpAvailable = [bool](Get-Module -ListAvailable -Name PnP.PowerShell)
    $sposAvailable = [bool](Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)

    if (-not $pnpAvailable -and -not $sposAvailable) {
        throw 'Neither PnP.PowerShell nor Microsoft.Online.SharePoint.PowerShell is installed. Install with: Install-Module PnP.PowerShell -Scope CurrentUser'
    }

    $upnList = @($users)

    if ($pnpAvailable) {
        Import-Module PnP.PowerShell -DisableNameChecking | Out-Null
        Write-Host "Connecting to SPO admin via PnP.PowerShell: $SpoAdminUrl" -ForegroundColor Cyan

        $connectArgs = @{ Url = $SpoAdminUrl; Interactive = $true }
        if ($PnPClientId) { $connectArgs['ClientId'] = $PnPClientId }

        try {
            Connect-PnPOnline @connectArgs
        }
        catch {
            if (-not $PnPClientId) {
                Write-Host "PnP connect failed without -PnPClientId. The default PnP Management Shell Entra app must be consented in this tenant," -ForegroundColor Yellow
                Write-Host "or pass -PnPClientId <appId> for a multi-tenant Entra app you have registered with Sites.FullControl.All." -ForegroundColor Yellow
            }
            throw
        }

        if ($PSCmdlet.ShouldProcess("$($upnList.Count) users", 'Request-PnPPersonalSite')) {
            try {
                Request-PnPPersonalSite -UserEmails $upnList
                Write-Host "Provisioning queued for $($upnList.Count) user(s) via PnP. Wait 5-15 min, then re-run smoke test." -ForegroundColor Green
            }
            finally {
                Disconnect-PnPOnline
            }
        }
        return
    }

    Import-Module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking | Out-Null
    Write-Host "Connecting to SPO admin via Microsoft.Online.SharePoint.PowerShell: $SpoAdminUrl" -ForegroundColor Cyan
    Connect-SPOService -Url $SpoAdminUrl

    if ($PSCmdlet.ShouldProcess("$($upnList.Count) users", 'Request-SPOPersonalSite')) {
        Request-SPOPersonalSite -UserEmails $upnList -NoWait
        Write-Host "Provisioning queued for $($upnList.Count) user(s). Wait 5-15 min, then re-run smoke test." -ForegroundColor Green
    }

    Disconnect-SPOService
    return
}

# --- Path B: Graph (poke /drive to trigger provisioning) ---
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph.Authentication module is not installed. Install with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
}
Import-Module Microsoft.Graph.Authentication | Out-Null

$graphScopes = @('User.Read.All', 'Files.ReadWrite.All', 'Sites.ReadWrite.All')
$graphEnv = switch ($Cloud) {
    'gcc'      { 'Global' }
    'gcchigh'  { 'USGov' }
    'dod'      { 'USGovDoD' }
    default    { 'Global' }
}

$ctx = Get-MgContext
if (-not $ctx -or -not $ctx.Account) {
    Write-Host "Connecting to Microsoft Graph ($graphEnv)..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes $graphScopes -Environment $graphEnv -NoWelcome
}

$ok = 0
$alreadyProvisioned = 0
$failed = 0
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($upn in $users) {
    if (-not $PSCmdlet.ShouldProcess($upn, 'Trigger OneDrive provisioning')) { continue }

    try {
        $null = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$upn/drive" -ErrorAction Stop
        Write-Host "  [ok] $upn — drive already provisioned" -ForegroundColor DarkGray
        $alreadyProvisioned++
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'NotFound|404') {
            try {
                $null = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$upn/drive/root" -ErrorAction Stop
                Write-Host "  [provisioning] $upn — kicked off" -ForegroundColor Green
                $ok++
            }
            catch {
                $err = $_.Exception.Message
                Write-Host "  [fail] $upn — $err" -ForegroundColor Red
                $failures.Add("$upn : $err")
                $failed++
            }
        }
        else {
            Write-Host "  [fail] $upn — $msg" -ForegroundColor Red
            $failures.Add("$upn : $msg")
            $failed++
        }
    }
}

Write-Host ''
Write-Host '--- Summary ---' -ForegroundColor Cyan
Write-Host "  Already provisioned : $alreadyProvisioned"
Write-Host "  Provisioning kicked : $ok"
Write-Host "  Failed              : $failed"

if ($failed -gt 0) {
    Write-Host ''
    Write-Host 'Graph cannot always trigger provisioning on its own. If failures persist,' -ForegroundColor Yellow
    Write-Host 're-run with -UseSpoPowerShell -SpoAdminUrl <https://tenant-admin.sharepoint.com>' -ForegroundColor Yellow
    Write-Host '  (requires SharePoint Admin role)' -ForegroundColor Yellow
}

if ($ok -gt 0 -or $failed -gt 0) {
    Write-Host ''
    Write-Host 'Wait 5-15 minutes, then re-run Invoke-SmokeTest.ps1.' -ForegroundColor Cyan
}
