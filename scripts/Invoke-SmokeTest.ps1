#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Sends emails and uploads files containing sensitive data to trigger DLP policies
    across Exchange, SharePoint, and OneDrive, then optionally validates audit matches.

.DESCRIPTION
    Three modes of operation:

    Auto-discover mode (default): run with no args. Connects to Microsoft Graph
    using the signed-in user (or current az login), discovers the tenant ID,
    primary .onmicrosoft.com domain, and two licensed mailbox-enabled users
    automatically. Works against ANY Purview tenant — no config file, no lab
    profile, no hardcoded tenant required. Ideal for teammates cloning the repo
    and running against their own tenant.

    Config mode: reads a lab config JSON to identify DLP policies and generate targeted
    test cases for each rule's SIT conditions. Useful when validating a specific
    deployed lab profile.

    Standalone mode: uses -TenantId, -Domain, and -Users parameters directly.
    Generates test cases for all common SITs (SSN, credit card, bank account,
    medical terms).

    For Exchange: sends emails between licensed users.
    For SharePoint/OneDrive: uploads text files with sensitive content to OneDrive.

    Each test item is tagged with a unique run ID for audit log correlation.

.PARAMETER TenantId
    (Standalone mode) Entra ID tenant ID. Used for Graph authentication.

.PARAMETER Domain
    (Standalone mode) Tenant domain (e.g., contoso.onmicrosoft.com).

.PARAMETER Users
    (Standalone mode) Array of licensed user UPNs. Minimum 2 required.

.PARAMETER ConfigPath
    (Config mode) Path to the lab configuration JSON file.

.PARAMETER LabProfile
    (Config mode) Lab profile shorthand (basic, ai, purview-sentinel).

.PARAMETER Cloud
    Cloud environment (commercial or gcc). Default: commercial.

.PARAMETER ValidateOnly
    Skip sending — only query the audit log for DLP matches.

.PARAMETER Since
    When using -ValidateOnly, the start time for the audit log query.
    Defaults to 1 hour ago.

.PARAMETER WaitMinutes
    After sending, poll the audit log for this many minutes (default: 0 = no wait).

.PARAMETER BurstActivity
    Generate high-volume activity (rapid emails, mass file uploads, sharing links)
    to trigger Insider Risk Management signals.

.PARAMETER SkipAuth
    Skip cloud authentication (for dry-run testing or pre-connected sessions).

.PARAMETER WhatIf
    Show what would be sent without actually sending.

.EXAMPLE
    # Auto-discover mode — zero arguments. Works in ANY Purview tenant.
    ./scripts/Invoke-SmokeTest.ps1

.EXAMPLE
    # Auto-discover + Insider Risk burst activity
    ./scripts/Invoke-SmokeTest.ps1 -BurstActivity

.EXAMPLE
    # Standalone mode — explicit tenant/domain/users (skips discovery)
    ./scripts/Invoke-SmokeTest.ps1 -TenantId "00000000-..." -Domain "contoso.onmicrosoft.com" -Users "alice@contoso.onmicrosoft.com","bob@contoso.onmicrosoft.com"

.EXAMPLE
    # Standalone with burst activity for Insider Risk
    ./scripts/Invoke-SmokeTest.ps1 -TenantId "00000000-..." -Domain "contoso.onmicrosoft.com" -Users "alice@contoso.onmicrosoft.com","bob@contoso.onmicrosoft.com" -BurstActivity

.EXAMPLE
    # Config mode — uses lab deployer config
    ./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -Cloud commercial

.EXAMPLE
    ./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -ValidateOnly -Since "2026-04-15T15:00:00"

.EXAMPLE
    ./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -BurstActivity -Cloud commercial
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Send')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Converting a short-lived Graph access token obtained from az CLI to SecureString for Connect-MgGraph. This is the documented pattern; the token is not a long-lived secret.')]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$Domain,

    [Parameter()]
    [string[]]$Users,

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$LabProfile,

    [Parameter()]
    [ValidateSet('commercial', 'gcc')]
    [string]$Cloud = 'commercial',

    [Parameter(ParameterSetName = 'Validate')]
    [switch]$ValidateOnly,

    [Parameter(ParameterSetName = 'Validate')]
    [datetime]$Since = (Get-Date).AddHours(-1),

    [Parameter(ParameterSetName = 'Send')]
    [int]$WaitMinutes = 0,

    [Parameter(ParameterSetName = 'Send')]
    [switch]$BurstActivity,

    [Parameter()]
    [switch]$SkipAuth
)

$ErrorActionPreference = 'Stop'

# --- Determine mode: auto-discover (default), standalone, or config ---
$standaloneMode = (-not [string]::IsNullOrWhiteSpace($TenantId)) -and
                  (-not [string]::IsNullOrWhiteSpace($Domain)) -and
                  ($null -ne $Users -and $Users.Count -ge 2)

$partialStandalone = ((-not [string]::IsNullOrWhiteSpace($TenantId)) -or
                     (-not [string]::IsNullOrWhiteSpace($Domain)) -or
                     ($null -ne $Users -and $Users.Count -gt 0)) -and -not $standaloneMode

$configMode = (-not [string]::IsNullOrWhiteSpace($ConfigPath)) -or
              (-not [string]::IsNullOrWhiteSpace($LabProfile))

if ($standaloneMode -and $configMode) {
    throw 'Use either standalone params (-TenantId/-Domain/-Users) or config params (-ConfigPath/-LabProfile), not both.'
}

$autoDiscoverMode = -not $standaloneMode -and -not $configMode

if ($partialStandalone -and -not $configMode) {
    Write-Host "  Partial standalone params supplied; missing values will be auto-discovered from Graph." -ForegroundColor DarkYellow
    $autoDiscoverMode = $true
}

# --- Auto-discover helpers ---
function Get-DiscoveredTenantContext {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $context = Get-MgContext
    if (-not $context) { throw 'Microsoft Graph is not connected. Call Connect-MgGraph first.' }

    $discoveredTenantId = $context.TenantId

    $org = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -ErrorAction Stop
    $orgData = @($org.value)[0]
    if (-not $orgData) { throw 'Unable to read tenant organization from Graph.' }

    $domains = @($orgData.verifiedDomains)
    $defaultDomain = ($domains | Where-Object { $_.isDefault -eq $true } | Select-Object -First 1).name
    $onMsDomain = ($domains | Where-Object { $_.name -like '*.onmicrosoft.com' } | Select-Object -First 1).name
    $discoveredDomain = if ($onMsDomain) { $onMsDomain } elseif ($defaultDomain) { $defaultDomain } else { $domains[0].name }

    return @{
        TenantId   = $discoveredTenantId
        Domain     = $discoveredDomain
        OrgDisplay = $orgData.displayName
    }
}

function Get-DiscoveredLicensedUsers {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [int]$MinCount = 2,
        [int]$MaxCount = 3
    )

    # Pull enabled users that have at least one license assigned and a mailbox-capable UPN.
    # Deterministic sort (by UPN) so repeated runs hit the same users.
    $uri = "https://graph.microsoft.com/v1.0/users?`$select=userPrincipalName,accountEnabled,assignedLicenses,mail,userType&`$top=200"
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
    $allUsers = @($resp.value)

    $candidates = $allUsers |
        Where-Object {
            $_.accountEnabled -eq $true -and
            $_.userType -ne 'Guest' -and
            $null -ne $_.assignedLicenses -and
            @($_.assignedLicenses).Count -gt 0 -and
            -not [string]::IsNullOrWhiteSpace($_.mail) -and
            $_.userPrincipalName -notlike '*#EXT#*'
        } |
        Sort-Object userPrincipalName |
        Select-Object -First $MaxCount

    if (@($candidates).Count -lt $MinCount) {
        throw "Auto-discovery found only $((@($candidates)).Count) licensed mailbox user(s); need at least $MinCount. Use -Users to specify explicitly."
    }

    return [string[]]@($candidates | ForEach-Object { $_.userPrincipalName })
}

if ($standaloneMode) {
    $prefix = 'SmokeTest'
    $domain = $Domain
    $labName = "Standalone Smoke Test ($Domain)"
}
elseif ($autoDiscoverMode) {
    $prefix = 'SmokeTest'
    # TenantId/Domain/Users populated after Graph connection below.
}
else {
    # Config mode — import deployer modules
    $repoRoot = Split-Path $PSScriptRoot
    $modulesPath = Join-Path $repoRoot 'modules'

    if (Test-Path (Join-Path $modulesPath 'Prerequisites.psm1')) {
        Import-Module (Join-Path $modulesPath 'Prerequisites.psm1') -Force
        foreach ($mod in (Get-ChildItem -Path $modulesPath -Filter '*.psm1')) {
            Import-Module $mod.FullName -Force
        }
    }
    else {
        throw "Deployer modules not found at '$modulesPath'. Use standalone mode (-TenantId/-Domain/-Users) or run from the repo root."
    }

    if (-not [string]::IsNullOrWhiteSpace($LabProfile) -and -not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        throw 'Specify either -LabProfile or -ConfigPath, not both.'
    }

    if (-not [string]::IsNullOrWhiteSpace($LabProfile)) {
        $profileConfigMap = Get-ProfileConfigMapping
        $configFileName = $profileConfigMap[$LabProfile]
        if (-not $configFileName) { throw "Unknown profile: $LabProfile" }
        $ConfigPath = Join-Path $repoRoot "configs/$Cloud/$configFileName"
    }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        throw 'Either -LabProfile, -ConfigPath, or standalone params (-TenantId/-Domain/-Users) required.'
    }

    $Config = Import-LabConfig -ConfigPath $ConfigPath
    $prefix = $Config.prefix
    $domain = $Config.domain
    $labName = $Config.labName
}

# --- Run ID ---
$runId = "SMOKE-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

if (-not $autoDiscoverMode) {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host " Purview DLP Smoke Test (Exchange + SharePoint + OneDrive)" -ForegroundColor Yellow
    Write-Host " Profile: $labName" -ForegroundColor Yellow
    Write-Host " Prefix: $prefix | Domain: $domain" -ForegroundColor Yellow
    Write-Host " Run ID: $runId" -ForegroundColor Yellow
    if ($standaloneMode) { Write-Host " Mode: Standalone" -ForegroundColor Yellow }
    Write-Host "========================================`n" -ForegroundColor Yellow
}
else {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host " Purview DLP Smoke Test (Auto-Discover Mode)" -ForegroundColor Yellow
    Write-Host " Run ID: $runId" -ForegroundColor Yellow
    Write-Host "========================================`n" -ForegroundColor Yellow
}

# --- SIT payload generators ---
# Each returns realistic email body snippets with enough surrounding context
# for Microsoft SIT classifiers to detect the sensitive info type.
$sitPayloads = @{
    'U.S. Social Security Number (SSN)' = @(
        "Please verify the employee's SSN on file: 078-05-1120. This is needed for the W-2 correction before end of quarter."
        "For the background check, the applicant provided Social Security Number 219-09-9999 on the intake form."
        "HR records show SSN 123-45-6789 for the terminated employee. Please confirm before we process the final paycheck."
    )
    'Credit Card Number' = @(
        "The client's credit card for the invoice payment is 4111-1111-1111-1111, expiration 12/27, CVV 123. Please process immediately."
        "Corporate card ending in 5500-0000-0000-0004 was used for the unauthorized purchase. Transaction ID: TXN-2026-8847."
        "Reimbursement request: employee submitted receipt with Visa 4012-8888-8888-1881 for the conference registration fee."
    )
    'U.S. Bank Account Number' = @(
        "Wire transfer details for vendor payment: routing number 021000021, account number 123456789012. Please initiate the transfer by Friday."
        "For direct deposit setup, use ABA routing 011401533 and checking account 9876543210. Bank: Bank of America."
        "Vendor ACH payment: ABA routing 071000013, bank account 112233445566. Amount: `$47,500.00 for Q4 consulting services."
    )
    'All Medical Terms And Conditions' = @(
        "Patient presented with acute myocardial infarction and was started on aspirin, clopidogrel, and heparin. Echocardiogram showed reduced ejection fraction of 35%. Cardiology consult requested for catheterization."
        "Employee accommodation request: diagnosed with major depressive disorder and generalized anxiety disorder per DSM-5 criteria. Treating psychiatrist recommends modified work schedule and ergonomic workstation assessment."
        "Workplace injury report: employee sustained a lumbar disc herniation at L4-L5 confirmed by MRI imaging. Radiculopathy with nerve impingement noted. Referred to orthopedic surgery for surgical evaluation and physical therapy."
    )
}

# --- Locations that cannot be tested via email or file upload ---
$nonTestableLocations = @('Devices', 'Browser', 'Network', 'EnterpriseAI', 'M365Copilot', 'CopilotExperiences')

# --- Testable locations ---
$exchangeLocations = @('Exchange')
$fileLocations = @('SharePoint', 'OneDrive', 'OneDriveForBusiness')

# --- Build test cases from config ---
function Get-DlpTestCases {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[hashtable]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $dlpWorkload = $Config.workloads.dlp
    if (-not $dlpWorkload -or -not $dlpWorkload.enabled) {
        Write-Host "  DLP workload is disabled in this config." -ForegroundColor DarkYellow
        return [System.Collections.Generic.List[hashtable]]::new()
    }

    $users = @($Config.workloads.testUsers.users | ForEach-Object {
        if ($_.upn) { $_.upn } elseif ($_.mailNickname) { "$($_.mailNickname)@$($Config.domain)" }
    })

    if ($users.Count -lt 2) {
        Write-Host "  Need at least 2 users for smoke test emails." -ForegroundColor Red
        return [System.Collections.Generic.List[hashtable]]::new()
    }

    $testCases = [System.Collections.Generic.List[hashtable]]::new()
    $userIdx = 0

    foreach ($policy in $dlpWorkload.policies) {
        $policyName = "$prefix-$($policy.name)"

        # Check locations — skip policies that only target non-testable locations
        $locations = @($policy.locations)
        if ($locations.Count -gt 0) {
            $hasTestableLocation = $false
            foreach ($loc in $locations) {
                if ($loc -notin $nonTestableLocations) { $hasTestableLocation = $true }
            }
            if (-not $hasTestableLocation) {
                Write-Host "  Skipping non-testable policy: $policyName ($($locations -join ', '))" -ForegroundColor DarkGray
                continue
            }
        }

        # Determine transport: email, file, or both
        $hasExchange = ($locations.Count -eq 0) -or ($locations | Where-Object { $_ -in $exchangeLocations })
        $hasFile = ($locations.Count -eq 0) -or ($locations | Where-Object { $_ -in $fileLocations })

        foreach ($rule in $policy.rules) {
            $ruleName = "$prefix-$($rule.name)"
            $sits = @($rule.sensitiveInfoTypes)

            if ($sits.Count -eq 0) {
                Write-Host "  Skipping label-only rule: $ruleName" -ForegroundColor DarkGray
                continue
            }

            foreach ($sit in $sits) {
                $payloads = $sitPayloads[$sit]
                if (-not $payloads) {
                    Write-Host "  No payload generator for SIT: $sit (rule: $ruleName)" -ForegroundColor DarkYellow
                    continue
                }

                $payload = $payloads[(Get-Random -Minimum 0 -Maximum $payloads.Count)]
                $from = $users[$userIdx % $users.Count]
                $to = $users[($userIdx + 1) % $users.Count]
                $userIdx++

                $subject = "[$RunId] $ruleName"

                # Email test case
                if ($hasExchange) {
                    $testCases.Add(@{
                        Policy    = $policyName
                        Rule      = $ruleName
                        SIT       = $sit
                        Transport = 'Email'
                        From      = $from
                        To        = $to
                        Subject   = $subject
                        Body      = "$payload`n`n---`nSmoke test: $RunId | Rule: $ruleName | SIT: $sit"
                    })
                }

                # File upload test case (OneDrive/SharePoint)
                if ($hasFile) {
                    $safeRuleName = ($ruleName -replace '[^a-zA-Z0-9-]', '_')
                    $testCases.Add(@{
                        Policy    = $policyName
                        Rule      = $ruleName
                        SIT       = $sit
                        Transport = 'OneDrive'
                        Owner     = $from
                        FileName  = "$RunId-$safeRuleName.txt"
                        Content   = "CONFIDENTIAL — FOR INTERNAL USE ONLY`n`n$payload`n`n---`nSmoke test: $RunId | Rule: $ruleName | SIT: $sit"
                    })
                }
            }
        }
    }

    return $testCases
}

# --- Send emails via Graph ---
function Send-SmokeTestEmails {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [array]$TestCases
    )

    $context = Get-MgContext
    if (-not $context -or (-not $context.Account -and -not $context.AppName -and -not $context.ClientId -and -not $context.TenantId)) {
        throw 'Microsoft Graph context is not available.'
    }

    $sent = 0
    $failed = 0

    foreach ($tc in $TestCases) {
        if ($PSCmdlet.ShouldProcess("$($tc.From) → $($tc.To): $($tc.Subject)", 'Send email')) {
            try {
                $body = @{
                    message = @{
                        subject      = $tc.Subject
                        body         = @{
                            contentType = 'Text'
                            content     = "From: $($tc.From)`nTo: $($tc.To)`n`n$($tc.Body)"
                        }
                        toRecipients = @(
                            @{ emailAddress = @{ address = $tc.To } }
                        )
                    }
                    saveToSentItems = $true
                }

                # Try send-as from the user's mailbox, fall back to admin
                $sendSuccess = $false
                try {
                    Invoke-MgGraphRequest -Method POST `
                        -Uri "https://graph.microsoft.com/v1.0/users/$($tc.From)/sendMail" `
                        -Body $body -ErrorAction Stop
                    $sendSuccess = $true
                }
                catch {
                    Invoke-MgGraphRequest -Method POST `
                        -Uri 'https://graph.microsoft.com/v1.0/me/sendMail' `
                        -Body $body -ErrorAction Stop
                    $sendSuccess = $true
                }

                if ($sendSuccess) {
                    Write-Host "  Sent: $($tc.From) -> $($tc.To)" -ForegroundColor Green
                    Write-Host "        Rule: $($tc.Rule) | SIT: $($tc.SIT)" -ForegroundColor DarkGray
                    $sent++
                }
            }
            catch {
                Write-Host "  FAIL: $($tc.Rule) — $_" -ForegroundColor Red
                $failed++
            }

            Start-Sleep -Milliseconds 500
        }
    }

    return @{ Sent = $sent; Failed = $failed }
}

# --- Upload files to OneDrive via Graph ---
function Send-SmokeTestFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [array]$TestCases
    )

    $context = Get-MgContext
    if (-not $context -or (-not $context.Account -and -not $context.AppName -and -not $context.ClientId -and -not $context.TenantId)) {
        throw 'Microsoft Graph context is not available.'
    }

    $uploaded = 0
    $failed = 0

    foreach ($tc in $TestCases) {
        if ($PSCmdlet.ShouldProcess("OneDrive: $($tc.FileName)", 'Upload file')) {
            try {
                $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($tc.Content)
                $stream = [System.IO.MemoryStream]::new($contentBytes)

                $folderPath = 'DLP-Smoke-Tests'

                # Try user's OneDrive first, fall back to /me/drive for delegated auth
                $uploadSuccess = $false
                try {
                    $uploadUri = "https://graph.microsoft.com/v1.0/users/$($tc.Owner)/drive/root:/$folderPath/$($tc.FileName):/content"
                    Invoke-MgGraphRequest -Method PUT -Uri $uploadUri `
                        -Body $stream -ContentType 'text/plain' -ErrorAction Stop | Out-Null
                    $uploadSuccess = $true
                    Write-Host "  Uploaded: $($tc.Owner)/DLP-Smoke-Tests/$($tc.FileName)" -ForegroundColor Green
                }
                catch {
                    $stream.Position = 0
                    $uploadUri = "https://graph.microsoft.com/v1.0/me/drive/root:/$folderPath/$($tc.FileName):/content"
                    Invoke-MgGraphRequest -Method PUT -Uri $uploadUri `
                        -Body $stream -ContentType 'text/plain' -ErrorAction Stop | Out-Null
                    $uploadSuccess = $true
                    Write-Host "  Uploaded: me/DLP-Smoke-Tests/$($tc.FileName)" -ForegroundColor Green
                }

                if ($uploadSuccess) {
                    Write-Host "           Rule: $($tc.Rule) | SIT: $($tc.SIT)" -ForegroundColor DarkGray
                    $uploaded++
                }
            }
            catch {
                Write-Host "  FAIL upload: $($tc.FileName) to $($tc.Owner) — $_" -ForegroundColor Red
                $failed++
            }
            finally {
                if ($stream) { $stream.Dispose() }
            }

            Start-Sleep -Milliseconds 500
        }
    }

    return @{ Uploaded = $uploaded; Failed = $failed }
}

# --- Burst activity for Insider Risk signals ---
function Send-BurstActivity {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$Users,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    Write-Host "`n--- Insider Risk Burst Activity ---" -ForegroundColor Cyan
    Write-Host "  Generating high-volume activity to trigger IRM signals...`n"

    $emailsSent = 0
    $filesUploaded = 0
    $sharesCreated = 0

    # Burst 1: Rapid email sends (10 emails from one user — data exfiltration pattern)
    $sourceUser = $Users[0]
    Write-Host "  [Burst] Rapid emails from $sourceUser (10 messages)..." -ForegroundColor White

    $subjects = @(
        "FW: Quarterly Revenue Forecast - CONFIDENTIAL"
        "FW: Board Presentation Draft - Internal Only"
        "FW: Customer List Export - Q4 2026"
        "FW: Compensation Data - HR Review"
        "FW: Strategic Plan 2027 - Executive Summary"
        "FW: Merger Analysis - Strictly Confidential"
        "FW: IP Portfolio Assessment - Legal Review"
        "FW: Employee Performance Rankings - HR"
        "FW: Vendor Contract Terms - Procurement"
        "FW: Financial Audit Findings - Draft"
    )

    for ($i = 0; $i -lt $subjects.Count; $i++) {
        $to = $Users[($i + 1) % $Users.Count]
        if ($PSCmdlet.ShouldProcess("$sourceUser -> ${to}: $($subjects[$i])", 'Send burst email')) {
            try {
                $body = @{
                    message = @{
                        subject      = "[$RunId] $($subjects[$i])"
                        body         = @{
                            contentType = 'Text'
                            content     = "Forwarding for your review. SSN reference: 078-05-1120. Card on file: 4111-1111-1111-1111.`n`nSmoke test burst: $RunId"
                        }
                        toRecipients = @(@{ emailAddress = @{ address = $to } })
                    }
                    saveToSentItems = $true
                }

                try {
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$sourceUser/sendMail" -Body $body -ErrorAction Stop
                }
                catch {
                    Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/me/sendMail' -Body $body -ErrorAction Stop
                }
                $emailsSent++
            }
            catch {
                Write-Host "    FAIL: $($subjects[$i]) — $_" -ForegroundColor Red
            }
            Start-Sleep -Milliseconds 300
        }
    }
    Write-Host "    $emailsSent emails sent" -ForegroundColor Green

    # Burst 2: Mass file uploads (15 files from one user — staging pattern)
    $uploadUser = if ($Users.Count -gt 1) { $Users[1] } else { $Users[0] }
    Write-Host "`n  [Burst] Mass file uploads to $uploadUser OneDrive (15 files)..." -ForegroundColor White

    $fileNames = @(
        "customer-database-export.csv"
        "employee-salary-data-2026.xlsx"
        "board-meeting-minutes-confidential.docx"
        "merger-target-financials.pdf"
        "intellectual-property-inventory.xlsx"
        "vendor-pricing-agreements.docx"
        "executive-compensation-review.xlsx"
        "client-contact-list-full.csv"
        "strategic-roadmap-2027.pptx"
        "audit-findings-draft.docx"
        "hr-investigation-notes.docx"
        "patent-portfolio-analysis.pdf"
        "revenue-forecast-model.xlsx"
        "confidential-legal-memo.docx"
        "departing-employee-handover.docx"
    )

    foreach ($fileName in $fileNames) {
        if ($PSCmdlet.ShouldProcess("OneDrive: $fileName", 'Upload burst file')) {
            try {
                $content = "CONFIDENTIAL - INTERNAL USE ONLY`n`nThis document contains sensitive business data.`nSSN: 219-09-9999`nAccount: routing 021000021 account 123456789012`n`nSmoke test burst: $RunId`nFile: $fileName"
                $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($content)
                $stream = [System.IO.MemoryStream]::new($contentBytes)

                $burstFolder = "DLP-Smoke-Tests/burst-$RunId"
                try {
                    $uploadUri = "https://graph.microsoft.com/v1.0/users/$uploadUser/drive/root:/$burstFolder/$fileName`:/content"
                    Invoke-MgGraphRequest -Method PUT -Uri $uploadUri -Body $stream -ContentType 'text/plain' -ErrorAction Stop | Out-Null
                }
                catch {
                    $stream.Position = 0
                    $uploadUri = "https://graph.microsoft.com/v1.0/me/drive/root:/$burstFolder/$fileName`:/content"
                    Invoke-MgGraphRequest -Method PUT -Uri $uploadUri -Body $stream -ContentType 'text/plain' -ErrorAction Stop | Out-Null
                }
                $filesUploaded++
            }
            catch {
                Write-Host "    FAIL upload: $fileName — $_" -ForegroundColor Red
            }
            finally {
                if ($stream) { $stream.Dispose() }
            }
            Start-Sleep -Milliseconds 200
        }
    }
    Write-Host "    $filesUploaded files uploaded" -ForegroundColor Green

    # Burst 3: Create sharing links
    Write-Host "`n  [Burst] Creating sharing links on uploaded files..." -ForegroundColor White

    $burstFolderPath = "DLP-Smoke-Tests/burst-$RunId"
    try {
        $listUri = $null
        try {
            $listUri = "https://graph.microsoft.com/v1.0/users/$uploadUser/drive/root:/$burstFolderPath`:/children"
            $driveItems = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
        }
        catch {
            $listUri = "https://graph.microsoft.com/v1.0/me/drive/root:/$burstFolderPath`:/children"
            $driveItems = Invoke-MgGraphRequest -Method GET -Uri $listUri -ErrorAction Stop
        }

        $itemsToShare = @($driveItems.value | Select-Object -First 5)
        $driveBase = if ($listUri -like "*/me/*") { "https://graph.microsoft.com/v1.0/me/drive" } else { "https://graph.microsoft.com/v1.0/users/$uploadUser/drive" }
        foreach ($item in $itemsToShare) {
            if ($PSCmdlet.ShouldProcess("$($item.name)", 'Create sharing link')) {
                try {
                    $shareBody = @{
                        type  = "view"
                        scope = "organization"
                    }
                    Invoke-MgGraphRequest -Method POST `
                        -Uri "$driveBase/items/$($item.id)/createLink" `
                        -Body $shareBody -ErrorAction Stop | Out-Null
                    $sharesCreated++
                }
                catch {
                    Write-Host "    FAIL share: $($item.name) — $_" -ForegroundColor Red
                }
            }
        }
        Write-Host "    $sharesCreated sharing links created" -ForegroundColor Green
    }
    catch {
        Write-Host "    Could not list files for sharing: $_" -ForegroundColor DarkYellow
    }

    Write-Host "`n  [Burst Summary] Emails: $emailsSent | Files: $filesUploaded | Shares: $sharesCreated" -ForegroundColor Cyan
    Write-Host "  IRM signals should appear within 24-48 hours." -ForegroundColor DarkGray

    return @{ Emails = $emailsSent; Files = $filesUploaded; Shares = $sharesCreated }
}

# --- Query audit log for DLP matches ---
function Test-DlpAuditMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$TestCases,

        [Parameter(Mandatory)]
        [datetime]$StartDate,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    Write-Host "`n--- Querying Unified Audit Log ---" -ForegroundColor Cyan
    Write-Host "  Run: $RunId"
    Write-Host "  Window: $($StartDate.ToString('yyyy-MM-dd HH:mm')) → $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    $endDate = (Get-Date).AddMinutes(5)
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $auditRecords = Search-UnifiedAuditLog -StartDate $StartDate -EndDate $endDate `
            -Operations 'DlpRuleMatch' -ResultSize 200 -ErrorAction Stop

        $matchCount = if ($auditRecords) { $auditRecords.Count } else { 0 }
        Write-Host "  Found $matchCount DLP audit records.`n" -ForegroundColor $(if ($matchCount -gt 0) { 'Green' } else { 'DarkYellow' })

        foreach ($tc in $TestCases) {
            $matched = $null
            if ($auditRecords) {
                $matched = $auditRecords | Where-Object {
                    $_.AuditData -like "*$($tc.Rule)*" -or $_.AuditData -like "*$($tc.Policy)*"
                }
            }

            $hitCount = if ($matched) { @($matched).Count } else { 0 }
            $results.Add([PSCustomObject]@{
                Status   = if ($hitCount -gt 0) { 'MATCHED' } else { 'PENDING' }
                Policy   = $tc.Policy
                Rule     = $tc.Rule
                SIT      = $tc.SIT
                Hits     = $hitCount
            })
        }
    }
    catch {
        Write-Host "  Audit log query failed: $_" -ForegroundColor Red
        Write-Host "  Run -ValidateOnly later after connecting via Connect-IPPSSession." -ForegroundColor DarkYellow

        foreach ($tc in $TestCases) {
            $results.Add([PSCustomObject]@{
                Status   = 'UNKNOWN'
                Policy   = $tc.Policy
                Rule     = $tc.Rule
                SIT      = $tc.SIT
                Hits     = 0
            })
        }
    }

    return $results
}

# ===================== MAIN =====================

# Auth
if (-not $SkipAuth) {
    # Resolve the tenant the caller wants us to target.
    #   1. Explicit -TenantId always wins (any mode, including auto-discover).
    #   2. Otherwise, -Cloud maps to the canonical commercial/GCC tenant GUID —
    #      but ONLY when the caller explicitly passed -Cloud (or we're in
    #      config mode). $PSBoundParameters lets us distinguish "user passed
    #      -Cloud commercial" from "user passed nothing and we got the default".
    #   3. Otherwise, null → Connect-MgGraph picks whatever session the CLI or
    #      browser offers (pure zero-arg auto-discover behaviour).
    $authTenantId = $null
    $cloudWasExplicit = $PSBoundParameters.ContainsKey('Cloud')
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
        $authTenantId = $TenantId
    }
    elseif ((-not $autoDiscoverMode) -or $cloudWasExplicit) {
        $authTenantId = switch ($Cloud) {
            'commercial' { 'f1b92d41-6d54-4102-9dd9-4208451314df' }
            'gcc' { '119e9fe0-c9d3-4a9d-be8b-c82d03fd0cd4' }
            default { $null }
        }
    }

    if ($ValidateOnly) {
        Write-Host "--- Connecting for audit log query ---" -ForegroundColor Cyan
        Connect-IPPSSession -ShowBanner:$false -ErrorAction Stop
        Write-Host "  IPPS connected.`n" -ForegroundColor Green
    }
    else {
        Write-Host "--- Connecting to cloud services ---" -ForegroundColor Cyan
        $graphScopes = @('Mail.Send', 'User.Read.All', 'Files.ReadWrite.All', 'Sites.ReadWrite.All', 'Organization.Read.All')

        # Prefer an existing az CLI session (works for OIDC in CI and `az login` locally),
        # but only when:
        #   (a) it's signed into the tenant we actually want (avoid wrong-tenant sends), AND
        #   (b) the resulting Graph token actually carries the scopes the smoke test needs.
        # Azure CLI's default consented scope set does NOT include Mail.Send /
        # Files.ReadWrite.All — reusing that token would land every send/upload in a
        # 403 wall. Decode the token's scp claim and fall through to interactive
        # Connect-MgGraph if the required scopes are missing.
        $azToken = $null
        $requiredScopes = @('Mail.Send', 'Files.ReadWrite.All')
        if (Get-Command az -ErrorAction SilentlyContinue) {
            try {
                $azAccount = az account show --query '{tenantId:tenantId}' -o json 2>$null | ConvertFrom-Json
                $azTenantMatches = $true
                if ($authTenantId -and $azAccount -and $azAccount.tenantId) {
                    $azTenantMatches = [string]::Equals([string]$azAccount.tenantId, [string]$authTenantId, [System.StringComparison]::OrdinalIgnoreCase)
                    if (-not $azTenantMatches) {
                        Write-Host "  az CLI signed into tenant $($azAccount.tenantId); caller requested $authTenantId. Skipping az token — will prompt interactively." -ForegroundColor DarkYellow
                    }
                }
                if ($azTenantMatches) {
                    $candidateToken = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv 2>$null
                    if ($candidateToken) {
                        $parts = $candidateToken.Split('.')
                        $scopesPresent = @()
                        if ($parts.Length -ge 2) {
                            $payload = $parts[1].Replace('-', '+').Replace('_', '/')
                            switch ($payload.Length % 4) {
                                2 { $payload += '==' }
                                3 { $payload += '=' }
                            }
                            try {
                                $claimsJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
                                $claims = $claimsJson | ConvertFrom-Json
                                if ($claims.scp) {
                                    $scopesPresent = $claims.scp -split '\s+'
                                }
                            }
                            catch {
                                $scopesPresent = @()
                            }
                        }
                        $missing = $requiredScopes | Where-Object { $_ -notin $scopesPresent }
                        if (@($missing).Count -eq 0) {
                            $azToken = $candidateToken
                        }
                        else {
                            Write-Host "  az CLI Graph token is missing scopes: $($missing -join ', '). Skipping az token — will prompt interactively for Graph sign-in." -ForegroundColor DarkYellow
                        }
                    }
                }
            }
            catch {
                $azToken = $null
            }
        }

        if ($azToken) {
            $secureToken = ConvertTo-SecureString $azToken -AsPlainText -Force
            Connect-MgGraph -AccessToken $secureToken -NoWelcome -ErrorAction Stop
        }
        elseif ($authTenantId) {
            Connect-MgGraph -TenantId $authTenantId -Scopes $graphScopes -NoWelcome -ErrorAction Stop
        }
        else {
            Connect-MgGraph -Scopes $graphScopes -NoWelcome -ErrorAction Stop
        }
        Write-Host "  Graph connected.`n" -ForegroundColor Green
    }
}

# Auto-discover tenant/domain/users after Graph is connected
if ($autoDiscoverMode) {
    Write-Host "--- Auto-discovering tenant context ---" -ForegroundColor Cyan

    $discovered = Get-DiscoveredTenantContext
    if ([string]::IsNullOrWhiteSpace($TenantId)) { $TenantId = $discovered.TenantId }
    if ([string]::IsNullOrWhiteSpace($Domain)) { $Domain = $discovered.Domain }
    $domain = $Domain
    $labName = if ($discovered.OrgDisplay) { "Auto-Discover ($($discovered.OrgDisplay))" } else { "Auto-Discover ($Domain)" }

    Write-Host "  Tenant: $($discovered.OrgDisplay) [$TenantId]" -ForegroundColor Green
    Write-Host "  Domain: $Domain" -ForegroundColor Green

    $autoPickedUsers = $false
    if (-not $Users -or $Users.Count -lt 2) {
        Write-Host "  Discovering licensed mailbox users..." -ForegroundColor DarkGray
        $Users = Get-DiscoveredLicensedUsers -MinCount 2 -MaxCount 3
        Write-Host "  Users: $($Users -join ', ')`n" -ForegroundColor Green
        $autoPickedUsers = $true
    }
    else {
        Write-Host "  Users (user-supplied): $($Users -join ', ')`n" -ForegroundColor Green
    }

    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host " Profile: $labName" -ForegroundColor Yellow
    Write-Host " Prefix: $prefix | Domain: $domain" -ForegroundColor Yellow
    Write-Host "========================================`n" -ForegroundColor Yellow

    # Safety gate: warn before sending real emails + OneDrive uploads to
    # auto-picked users. Skipped under -WhatIf, -ValidateOnly, or -SkipAuth.
    if ($autoPickedUsers -and -not $WhatIfPreference -and -not $ValidateOnly -and -not $SkipAuth) {
        Write-Host "WARNING: auto-discover picked the first 2 licensed mailbox users (alphabetical)." -ForegroundColor Yellow
        Write-Host "         This script will send emails with fake SSN / credit-card / medical payloads" -ForegroundColor Yellow
        Write-Host "         AND upload files to OneDrive for the users above. Make sure these are" -ForegroundColor Yellow
        Write-Host "         lab accounts, not executives or real employees.`n" -ForegroundColor Yellow
        Write-Host "         Preview with -WhatIf first, or pass -Users explicitly to target lab accounts." -ForegroundColor DarkYellow
        $response = Read-Host "`nProceed with these users? (y/N)"
        if ($response -notmatch '^(y|yes)$') {
            Write-Host "  Aborted by user." -ForegroundColor DarkYellow
            exit 0
        }
        Write-Host ''
    }
}

# Build test cases
Write-Host "--- Building test cases ---" -ForegroundColor Cyan

if ($standaloneMode -or $autoDiscoverMode) {
    # Standalone/auto-discover: generate test cases for all SIT types
    $testCases = [System.Collections.Generic.List[hashtable]]::new()
    $sitNames = @(
        'U.S. Social Security Number (SSN)'
        'Credit Card Number'
        'U.S. Bank Account Number'
        'All Medical Terms And Conditions'
    )
    $userIdx = 0
    foreach ($sitName in $sitNames) {
        $payloads = $sitPayloads[$sitName]
        if (-not $payloads) { continue }
        $payload = $payloads[(Get-Random -Minimum 0 -Maximum $payloads.Count)]
        $from = $Users[$userIdx % $Users.Count]
        $to = $Users[($userIdx + 1) % $Users.Count]
        $userIdx++

        $safeSit = ($sitName -replace '[^a-zA-Z0-9-]', '_')

        # Email test case
        $testCases.Add(@{
            Policy    = 'DLP'
            Rule      = "$prefix-$sitName"
            SIT       = $sitName
            Transport = 'Email'
            From      = $from
            To        = $to
            Subject   = "[$runId] DLP Test - $sitName"
            Body      = "$payload`n`n---`nSmoke test: $runId | SIT: $sitName"
        })

        # File upload test case
        $testCases.Add(@{
            Policy    = 'DLP'
            Rule      = "$prefix-$sitName"
            SIT       = $sitName
            Transport = 'OneDrive'
            Owner     = $from
            FileName  = "$runId-$safeSit.txt"
            Content   = "CONFIDENTIAL`n`n$payload`n`n---`nSmoke test: $runId | SIT: $sitName"
        })
    }
}
else {
    # Config mode: derive test cases from deployed DLP policies
    $testCases = Get-DlpTestCases -Config $Config -RunId $runId
}

if ($testCases.Count -eq 0) {
    Write-Host "`nNo testable DLP test cases found." -ForegroundColor DarkYellow
    exit 0
}

$emailCases = @($testCases | Where-Object { $_.Transport -eq 'Email' })
$fileCases = @($testCases | Where-Object { $_.Transport -eq 'OneDrive' })
$policyCount = @($testCases | ForEach-Object { $_.Policy } | Sort-Object -Unique).Count
Write-Host "`n  $($testCases.Count) test cases ($($emailCases.Count) emails + $($fileCases.Count) file uploads) targeting $policyCount policies`n"

# Show test matrix
Write-Host "--- Test Matrix ---" -ForegroundColor Cyan
foreach ($tc in $testCases) {
    $icon = if ($tc.Transport -eq 'Email') { 'Mail' } else { 'File' }
    Write-Host "  [$icon] $($tc.Rule)" -ForegroundColor White
    if ($tc.Transport -eq 'Email') {
        Write-Host "    SIT: $($tc.SIT) | $($tc.From) → $($tc.To)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "    SIT: $($tc.SIT) | $($tc.Owner) OneDrive → $($tc.FileName)" -ForegroundColor DarkGray
    }
}

# Validate-only mode
if ($ValidateOnly) {
    $results = Test-DlpAuditMatches -TestCases $testCases -StartDate $Since -RunId $runId
    if ($results.Count -gt 0) {
        Write-Host "`n--- Validation Results ---" -ForegroundColor Cyan
        $results | Format-Table -Property Status, Policy, Rule, SIT, Hits -AutoSize
        $matchedCount = @($results | Where-Object { $_.Status -eq 'MATCHED' }).Count
        Write-Host "  $matchedCount/$($results.Count) rules matched.`n"
    }
    exit 0
}

# Send emails + upload files
Write-Host "`n--- Sending smoke test data ---" -ForegroundColor Cyan
$sendTime = Get-Date
$emailResult = @{ Sent = 0; Failed = 0 }
$fileResult = @{ Uploaded = 0; Failed = 0 }

if ($emailCases.Count -gt 0) {
    Write-Host "`n  Emails ($($emailCases.Count)):" -ForegroundColor White
    $emailResult = Send-SmokeTestEmails -TestCases $emailCases
}

if ($fileCases.Count -gt 0) {
    Write-Host "`n  OneDrive uploads ($($fileCases.Count)):" -ForegroundColor White
    $fileResult = Send-SmokeTestFiles -TestCases $fileCases
}

Write-Host "`n--- Send Summary ---" -ForegroundColor Cyan
Write-Host "  Emails sent: $($emailResult.Sent) | Failed: $($emailResult.Failed)"
Write-Host "  Files uploaded: $($fileResult.Uploaded) | Failed: $($fileResult.Failed)"
Write-Host "  Run ID: $runId"
Write-Host "  Sent at: $($sendTime.ToString('yyyy-MM-dd HH:mm:ss'))"

# If every send AND every upload failed, surface the most likely root cause so
# the user isn't left staring at a wall of 403 / 404 dumps.
if ($emailCases.Count -gt 0 -and $emailResult.Sent -eq 0 -and
    $fileCases.Count -gt 0 -and $fileResult.Uploaded -eq 0) {

    $ctx = Get-MgContext
    $signedInAccount = if ($ctx) { [string]$ctx.Account } else { '<unknown>' }

    Write-Host "`n--- Auth model hint ---" -ForegroundColor Yellow
    Write-Host "  All 403 ErrorAccessDenied on /me/sendMail AND 404 on /me/drive usually means:" -ForegroundColor Yellow
    Write-Host "    • the signed-in account ($signedInAccount) has no mailbox license, and" -ForegroundColor Yellow
    Write-Host "    • that account has never signed in to OneDrive so /me/drive 404s." -ForegroundColor Yellow
    Write-Host "`n  Fix options (pick one):" -ForegroundColor Yellow
    Write-Host "    1. Sign in interactively AS one of the test users (license: M365 E5 / G5 or E3 + mailbox)." -ForegroundColor Yellow
    Write-Host "       That user needs Mail.Send delegated + OneDrive provisioned (visit onedrive.com once)." -ForegroundColor Yellow
    Write-Host "       Disconnect first:  Disconnect-MgGraph" -ForegroundColor Yellow
    Write-Host "    2. Pre-provision OneDrive for the auto-picked users:" -ForegroundColor Yellow
    Write-Host "         ./scripts/Request-OneDriveProvisioning.ps1 -LabProfile <profile> -Wait" -ForegroundColor Yellow
    Write-Host "    3. Pass -Users <upn1>,<upn2> to target specific licensed lab accounts (still need scope + mailbox + OneDrive)." -ForegroundColor Yellow
    Write-Host "`n  See SMOKETEST.md troubleshooting section for the full matrix." -ForegroundColor Yellow
}

# Burst activity for Insider Risk
if ($BurstActivity) {
    $burstUsers = if ($standaloneMode -or $autoDiscoverMode) {
        $Users
    }
    else {
        @($Config.workloads.testUsers.users | ForEach-Object {
            if ($_.upn) { $_.upn } elseif ($_.mailNickname) { "$($_.mailNickname)@$($Config.domain)" }
        })
    }
    $burstResult = Send-BurstActivity -Users $burstUsers -RunId $runId
}

# Expected outcomes
Write-Host "`n--- Expected DLP Alerts ---" -ForegroundColor Cyan
Write-Host "  Alerts appear in Purview within 15-60 minutes:" -ForegroundColor DarkGray
Write-Host "  https://purview.microsoft.com/datalossprevention/alerts" -ForegroundColor DarkGray
Write-Host "  Activity Explorer: https://purview.microsoft.com/datalossprevention/activityexplorer`n" -ForegroundColor DarkGray
foreach ($tc in $testCases) {
    $icon = if ($tc.Transport -eq 'Email') { 'Mail' } else { 'File' }
    Write-Host "  [$icon] $($tc.Policy)" -ForegroundColor White
    Write-Host "    Rule: $($tc.Rule) | SIT: $($tc.SIT)" -ForegroundColor DarkGray
}

if ($BurstActivity) {
    Write-Host "`n--- Expected Insider Risk Signals ---" -ForegroundColor Cyan
    Write-Host "  IRM alerts: https://purview.microsoft.com/insiderriskmanagement/alerts" -ForegroundColor DarkGray
    Write-Host "  Signals take 24-48 hours to process into risk scores." -ForegroundColor DarkGray
    Write-Host "  Activity generated: $($burstResult.Emails) rapid emails, $($burstResult.Files) file uploads, $($burstResult.Shares) sharing links`n" -ForegroundColor DarkGray
}

# Optional wait + validate
if ($WaitMinutes -gt 0) {
    Write-Host "`n--- Waiting $WaitMinutes minutes for DLP processing ---" -ForegroundColor Cyan

    try {
        Connect-IPPSSession -ShowBanner:$false -ErrorAction Stop
    }
    catch {
        Write-Host "  Could not connect to IPPS for validation: $_" -ForegroundColor DarkYellow
        Write-Host "  Validate later with:" -ForegroundColor DarkYellow
        if ($standaloneMode -or $autoDiscoverMode) {
            Write-Host "  ./scripts/Invoke-SmokeTest.ps1 -ValidateOnly -Since '$($sendTime.ToString('o'))'`n" -ForegroundColor White
        }
        else {
            Write-Host "  ./scripts/Invoke-SmokeTest.ps1 -LabProfile $LabProfile -ValidateOnly -Since '$($sendTime.ToString('o'))'`n" -ForegroundColor White
        }
        exit 0
    }

    $pollInterval = 30
    $elapsed = 0
    $waitSeconds = $WaitMinutes * 60
    $results = @()

    while ($elapsed -lt $waitSeconds) {
        $remaining = [math]::Round(($waitSeconds - $elapsed) / 60, 1)
        Write-Host "  Polling ($remaining min remaining)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval

        $results = Test-DlpAuditMatches -TestCases $testCases -StartDate $sendTime -RunId $runId
        $matchedCount = @($results | Where-Object { $_.Status -eq 'MATCHED' }).Count

        if ($matchedCount -eq $testCases.Count) {
            Write-Host "`n  All $matchedCount test cases matched!" -ForegroundColor Green
            break
        }
        elseif ($matchedCount -gt 0) {
            Write-Host "  $matchedCount/$($testCases.Count) matched so far..." -ForegroundColor DarkYellow
        }
    }

    if ($results.Count -gt 0) {
        Write-Host "`n--- Final Results ---" -ForegroundColor Cyan
        $results | Format-Table -Property Status, Policy, Rule, SIT, Hits -AutoSize
    }
}

Write-Host "`n--- To validate later ---" -ForegroundColor Cyan
if ($standaloneMode -or $autoDiscoverMode) {
    Write-Host "  ./scripts/Invoke-SmokeTest.ps1 -ValidateOnly -Since '$($sendTime.ToString('o'))'`n" -ForegroundColor White
}
else {
    Write-Host "  ./scripts/Invoke-SmokeTest.ps1 -LabProfile $LabProfile -ValidateOnly -Since '$($sendTime.ToString('o'))'`n" -ForegroundColor White
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host " Smoke Test Complete" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Yellow
