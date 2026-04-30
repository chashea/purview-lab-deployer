#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Fire synthetic DLP test traffic on the lab tenant:
      1. Send an email with SSN payload (Exchange DLP path)
      2. Upload a file with credit-card payload to OneDrive (SharePoint/ODB path)

.DESCRIPTION
    Uses a manual device-code flow against the Microsoft Graph Command Line
    Tools public client so the user_code prints visibly even when pwsh runs
    from bash without a real TTY. Connect-MgGraph -UseDeviceCode swallows
    the prompt in that context and the script gets stuck.

    Payload matches built-in "U.S. Social Security Number (SSN)" and
    "Credit Card Number" SITs at minCount=1 (what basic-demo ships).

.PARAMETER TenantId
    Entra ID tenant for device code auth. Required.

.PARAMETER ExtraRecipient
    Optional extra To/CC recipient UPN for the test email.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter()] [string]$ExtraRecipient
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'modules' 'Logging.psm1') -Force

# Microsoft Graph Command Line Tools (public client, well-known ID)
$clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$scope = 'https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/Files.ReadWrite https://graph.microsoft.com/User.Read offline_access'
$authority = "https://login.microsoftonline.com/$TenantId"

Write-LabLog -Message "Requesting device code (tenant $TenantId)..." -Level Info
$deviceReq = @{
    client_id = $clientId
    scope     = $scope
}
$deviceResp = Invoke-RestMethod -Method POST -Uri "$authority/oauth2/v2.0/devicecode" -Body $deviceReq -ContentType 'application/x-www-form-urlencoded'

Write-Host ''
Write-Host '============================================================'
Write-Host 'DEVICE CODE AUTH' -ForegroundColor Cyan
Write-Host "  URL : $($deviceResp.verification_uri)"
Write-Host "  CODE: $($deviceResp.user_code)" -ForegroundColor Yellow
Write-Host '============================================================'
Write-Host "Open the URL, paste the CODE, sign in as a GCC admin with Mail.Send."
Write-Host ''

$tokenBody = @{
    grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
    client_id   = $clientId
    device_code = $deviceResp.device_code
}

$token = $null
$expiresAt = (Get-Date).AddSeconds([int]$deviceResp.expires_in)
$interval = [int]$deviceResp.interval
if ($interval -le 0) { $interval = 5 }

while (-not $token) {
    if ((Get-Date) -gt $expiresAt) {
        throw "Device code expired before sign-in completed."
    }
    Start-Sleep -Seconds $interval
    try {
        $token = Invoke-RestMethod -Method POST -Uri "$authority/oauth2/v2.0/token" -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
    }
    catch {
        $errBody = $null
        try { $errBody = $_.ErrorDetails.Message | ConvertFrom-Json } catch { $null }
        if ($errBody -and $errBody.error -eq 'authorization_pending') {
            Write-Host '  ...waiting for sign-in' -ForegroundColor DarkGray
            continue
        }
        if ($errBody -and $errBody.error -eq 'slow_down') {
            $interval += 5
            continue
        }
        throw "Device code token error: $(if ($errBody) { $errBody.error_description } else { $_.Exception.Message })"
    }
}

$headers = @{ Authorization = "Bearer $($token.access_token)" }
Write-LabLog -Message "Token acquired (tid=$TenantId, scope=$($token.scope))" -Level Success

# Resolve admin UPN from /me
$me = Invoke-RestMethod -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -Headers $headers
$adminUpn = [string]$me.userPrincipalName
Write-LabLog -Message "Signed in as: $adminUpn (id=$($me.id))" -Level Info

# --- 1. Email with SSN payload ---
$mailSubject = "[DLP TEST] Employee intake form - $(Get-Date -Format 'HH:mm:ss')"
$mailBody = @"
DLP synthetic test payload - please ignore.

The following SSNs are fabricated for Microsoft Purview DLP policy testing:
  SSN: 123-45-6789
  SSN: 987-65-4321
  SSN: 555-12-3456

Timestamp: $(Get-Date -Format 'u')
"@

$toList = @(@{ emailAddress = @{ address = $adminUpn } })
$ccList = @()
if ($ExtraRecipient) {
    $ccList = @(@{ emailAddress = @{ address = $ExtraRecipient } })
}

$sendBody = @{
    message = @{
        subject      = $mailSubject
        body         = @{ contentType = 'Text'; content = $mailBody }
        toRecipients = $toList
    }
    saveToSentItems = $true
}
if ($ccList.Count -gt 0) {
    $sendBody.message.ccRecipients = $ccList
}

Write-LabLog -Message "Sending SSN-payload email ($adminUpn -> $adminUpn$(if ($ExtraRecipient) { ', cc '+$ExtraRecipient }))" -Level Info
try {
    Invoke-RestMethod -Method POST -Uri 'https://graph.microsoft.com/v1.0/me/sendMail' -Headers $headers -Body ($sendBody | ConvertTo-Json -Depth 10) -ContentType 'application/json'
    Write-LabLog -Message "Email submitted. Subject: $mailSubject" -Level Success
}
catch {
    Write-LabLog -Message "sendMail failed: $($_.Exception.Message)" -Level Error
    throw
}

# --- 2. Upload file with credit-card payload to OneDrive ---
$ccFileContent = @"
DLP synthetic test payload - please ignore.

Credit card numbers (test values used by DLP validation):
  4916-5024-0027-3258
  5500-0000-0000-0004
  3782-822463-10005

Timestamp: $(Get-Date -Format 'u')
"@

$ccFileName = "dlp-test-creditcards-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$uploadUri = "https://graph.microsoft.com/v1.0/me/drive/root:/$ccFileName`:/content"
Write-LabLog -Message "Uploading CC-payload file to OneDrive: $ccFileName" -Level Info
try {
    $uploaded = Invoke-RestMethod -Method PUT -Uri $uploadUri -Headers $headers -Body $ccFileContent -ContentType 'text/plain'
    Write-LabLog -Message "OneDrive upload complete. Item id=$($uploaded.id)  webUrl=$($uploaded.webUrl)" -Level Success
}
catch {
    Write-LabLog -Message "OneDrive upload failed: $($_.Exception.Message)" -Level Error
    throw
}

Write-Host ''
Write-Host 'Done. Expected windows:' -ForegroundColor Cyan
Write-Host '  Exchange DLP  ~60 seconds (E5/G5) for the audit entry + alert.'
Write-Host '  OneDrive DLP  up to ~15 min for initial scan, alert may take up to 3h.'
Write-Host ''
Write-Host 'Re-run: ./scripts/Test-DlpAlertReady.ps1 -LabProfile basic -Cloud gcc'
