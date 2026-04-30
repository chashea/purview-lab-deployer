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

This script reads the lab profile, extracts the test users, and triggers
OneDrive provisioning for each one via:

  1. Graph /users/{upn}/drive  — auto-provisions on demand for many tenants
  2. SharePoint Online Request-SPOPersonalSite (preferred, faster) — used if
     -UseSpoPowerShell is passed and the SPO module is available

After running this script, wait 5–15 minutes for SPO to finish provisioning
the personal sites, then re-run Invoke-SmokeTest.ps1.

.PARAMETER LabProfile
Lab profile name (basic, financial, healthcare, etc.). Used to look up
configs/<cloud>/<profile>-demo.json.

.PARAMETER ConfigPath
Explicit config file path. Overrides -LabProfile.

.PARAMETER Cloud
Azure cloud (commercial, gcc, gcchigh, dod). Default: commercial.

.PARAMETER UseSpoPowerShell
Use the Microsoft.Online.SharePoint.PowerShell module's Request-SPOPersonalSite
cmdlet instead of poking Graph. Faster and more reliable, but requires the
SPO admin URL and the SharePoint Admin role.

.PARAMETER SpoAdminUrl
Required when -UseSpoPowerShell is set. e.g. https://contoso-admin.sharepoint.com

.EXAMPLE
./scripts/Initialize-TestUserOneDrives.ps1 -LabProfile basic -Cloud gcc

.EXAMPLE
./scripts/Initialize-TestUserOneDrives.ps1 -LabProfile basic -Cloud gcc `
  -UseSpoPowerShell -SpoAdminUrl https://mngenvmcap659995-admin.sharepoint.com
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

    [string]$SpoAdminUrl
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
foreach ($u in @($config.users)) {
    if ($u.upn) { [void]$users.Add($u.upn) }
}

if ($users.Count -eq 0) {
    throw 'No users found in config.users[].upn'
}

Write-Host "Found $($users.Count) test user(s)" -ForegroundColor Cyan

# --- Path A: SPO PowerShell (preferred) ---
if ($UseSpoPowerShell) {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
        throw 'Microsoft.Online.SharePoint.PowerShell module is not installed. Install with: Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser'
    }

    Import-Module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking | Out-Null

    Write-Host "Connecting to SPO admin: $SpoAdminUrl" -ForegroundColor Cyan
    Connect-SPOService -Url $SpoAdminUrl

    $upnList = @($users)
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
