#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Close the loop after Invoke-DlpTestTraffic.ps1:
      1. Pull DLP alerts via Graph /security/alerts_v2 for the last 2h
      2. Delete the OneDrive test file
      3. Delete the test email from admin's Inbox and SentItems

.PARAMETER TenantId
    GCC tenant ID (required).

.PARAMETER OneDriveItemId
    driveItem id of the uploaded CC test file.

.PARAMETER SubjectSubstring
    Substring on the test email subject used to locate + delete it. The mail
    is delivered with "[Secure]" prepended by the default Office 365 DLP
    encryption rule, so the original subject is a reliable substring anchor.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$OneDriveItemId,
    [Parameter()] [string]$SubjectSubstring = '[DLP TEST] Employee intake form'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules' 'Logging.psm1') -Force

$clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$scope = 'https://graph.microsoft.com/Mail.ReadWrite https://graph.microsoft.com/Files.ReadWrite https://graph.microsoft.com/SecurityAlert.Read.All https://graph.microsoft.com/User.Read offline_access'
$authority = "https://login.microsoftonline.com/$TenantId"

Write-LabLog -Message "Requesting device code (tenant $TenantId)..." -Level Info
$deviceResp = Invoke-RestMethod -Method POST -Uri "$authority/oauth2/v2.0/devicecode" -Body @{ client_id = $clientId; scope = $scope } -ContentType 'application/x-www-form-urlencoded'

Write-Host ''
Write-Host '============================================================'
Write-Host 'DEVICE CODE AUTH' -ForegroundColor Cyan
Write-Host "  URL : $($deviceResp.verification_uri)"
Write-Host "  CODE: $($deviceResp.user_code)" -ForegroundColor Yellow
Write-Host '============================================================'

$tokenBody = @{
    grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
    client_id   = $clientId
    device_code = $deviceResp.device_code
}
$token = $null
$expiresAt = (Get-Date).AddSeconds([int]$deviceResp.expires_in)
$interval = [Math]::Max([int]$deviceResp.interval, 5)

while (-not $token) {
    if ((Get-Date) -gt $expiresAt) { throw "Device code expired." }
    Start-Sleep -Seconds $interval
    try {
        $token = Invoke-RestMethod -Method POST -Uri "$authority/oauth2/v2.0/token" -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
    } catch {
        $errBody = $null
        try { $errBody = $_.ErrorDetails.Message | ConvertFrom-Json } catch { $null }
        if ($errBody -and $errBody.error -eq 'authorization_pending') { Write-Host '  ...waiting for sign-in' -ForegroundColor DarkGray; continue }
        if ($errBody -and $errBody.error -eq 'slow_down') { $interval += 5; continue }
        throw "Device code token error: $(if ($errBody) { $errBody.error_description } else { $_.Exception.Message })"
    }
}

$headers = @{ Authorization = "Bearer $($token.access_token)" }
$me = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -Headers $headers
Write-LabLog -Message "Signed in as: $($me.userPrincipalName)" -Level Success

# --- 1. Pull DLP alerts ---
$since = (Get-Date).ToUniversalTime().AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ssZ')
$alertUri = "https://graph.microsoft.com/v1.0/security/alerts_v2?`$filter=serviceSource eq 'dataLossPrevention' and createdDateTime ge $since&`$top=25"
Write-LabLog -Message "Querying /security/alerts_v2 (DLP, since $since)" -Level Info
try {
    $alertResp = Invoke-RestMethod -Method GET -Uri $alertUri -Headers $headers
    $alerts = @($alertResp.value)
    Write-Host ("Returned $($alerts.Count) DLP alert(s):") -ForegroundColor Cyan
    foreach ($a in $alerts | Select-Object -First 10) {
        Write-Host ("  [{0}] {1}  severity={2}  createdDateTime={3}  assignedTo={4}" -f $a.id, $a.title, $a.severity, $a.createdDateTime, $a.assignedTo)
        Write-Host ("    status={0}  detectionSource={1}  description={2}" -f $a.status, $a.detectionSource, $a.description)
    }
} catch {
    Write-LabLog -Message "alerts_v2 query failed: $($_.Exception.Message)" -Level Warning
}

# --- 2. Delete OneDrive file ---
Write-LabLog -Message "Deleting OneDrive item $OneDriveItemId" -Level Info
try {
    Invoke-RestMethod -Method DELETE -Uri "https://graph.microsoft.com/v1.0/me/drive/items/$OneDriveItemId" -Headers $headers | Out-Null
    Write-LabLog -Message "OneDrive test file deleted." -Level Success
} catch {
    Write-LabLog -Message "OneDrive delete failed: $($_.Exception.Message)" -Level Warning
}

# --- 3. Delete test emails from admin mailbox ---
$searchFilter = "contains(subject,'$SubjectSubstring')"
$encodedFilter = [uri]::EscapeDataString($searchFilter)

foreach ($folder in @('inbox', 'sentitems')) {
    $listUri = "https://graph.microsoft.com/v1.0/me/mailFolders/$folder/messages?`$filter=$encodedFilter&`$top=25&`$select=id,subject,receivedDateTime,from"
    Write-LabLog -Message "Searching $folder for test emails..." -Level Info
    try {
        $resp = Invoke-RestMethod -Method GET -Uri $listUri -Headers $headers
        $msgs = @($resp.value)
        Write-Host ("  {0}: {1} match(es)" -f $folder, $msgs.Count)
        foreach ($m in $msgs) {
            try {
                Invoke-RestMethod -Method DELETE -Uri "https://graph.microsoft.com/v1.0/me/messages/$($m.id)" -Headers $headers | Out-Null
                Write-Host "    deleted: $($m.subject)"
            } catch {
                Write-Host "    delete FAILED for $($m.id): $($_.Exception.Message)"
            }
        }
    } catch {
        $fname = $folder
        Write-LabLog -Message "$fname search failed: $($_.Exception.Message)" -Level Warning
    }
}

Write-Host ''
Write-Host 'Cleanup complete. Note: the copy in mahmed@... inbox remains (out of scope for admin delegated perms).' -ForegroundColor Cyan
