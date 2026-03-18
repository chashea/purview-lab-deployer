#Requires -Version 7.0

<#
.SYNOPSIS
    Test data workload module for purview-lab-deployer.
    Sends test emails via Microsoft Graph to trigger Purview policies.
#>

function Send-TestData {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    # Send all emails from the signed-in admin account to avoid permission issues
    $context = Get-MgContext
    if (-not $context -or [string]::IsNullOrWhiteSpace($context.Account)) {
        throw 'Microsoft Graph context is not available for Send-TestData.'
    }
    $adminUpn = $context.Account
    $tenantId = [string]$context.TenantId
    $scopes = @($context.Scopes)

    $userPrincipalNameLookup = @{}
    $missingIdentities = [System.Collections.Generic.List[string]]::new()

    foreach ($email in $Config.workloads.testData.emails) {
        foreach ($identity in @($email.from, $email.to)) {
            if ([string]::IsNullOrWhiteSpace([string]$identity)) {
                continue
            }

            if ($userPrincipalNameLookup.ContainsKey($identity)) {
                continue
            }

            $resolvedUser = Get-LabUserByIdentity -Identity $identity -DefaultDomain $Config.domain
            if ($resolvedUser -and -not [string]::IsNullOrWhiteSpace([string]$resolvedUser.UserPrincipalName)) {
                $userPrincipalNameLookup[$identity] = [string]$resolvedUser.UserPrincipalName
            }
            else {
                $missingIdentities.Add([string]$identity)
            }
        }
    }

    if ($missingIdentities.Count -gt 0) {
        $missingSummary = (($missingIdentities | Sort-Object -Unique) -join ', ')
        throw "TestData references users that were not found in Microsoft Graph: $missingSummary"
    }

    $sentEmails = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($email in $Config.workloads.testData.emails) {
        $fromUpn = [string]$userPrincipalNameLookup[[string]$email.from]
        $toUpn = [string]$userPrincipalNameLookup[[string]$email.to]

        if ($PSCmdlet.ShouldProcess("Send email to $toUpn (on behalf of $fromUpn)`: $($email.subject)")) {
            $body = @{
                message = @{
                    subject      = $email.subject
                    body         = @{
                        contentType = 'Text'
                        content     = "From: $fromUpn`n`n$($email.body)"
                    }
                    toRecipients = @(
                        @{
                            emailAddress = @{
                                address = $toUpn
                            }
                        }
                    )
                }
                saveToSentItems = $true
            }

            $sent = $false
            for ($attempt = 1; $attempt -le 2; $attempt++) {
                try {
                    if (Get-Command -Name Send-MgUserMail -ErrorAction SilentlyContinue) {
                        Send-MgUserMail -UserId $adminUpn -BodyParameter $body -ErrorAction Stop
                    }
                    else {
                        Invoke-MgGraphRequest -Method POST `
                            -Uri "/v1.0/users/$adminUpn/sendMail" `
                            -Body $body `
                            -ErrorAction Stop
                    }

                    Write-LabLog -Message "Sent email from $fromUpn to $toUpn`: $($email.subject)" -Level Success
                    $sentEmails.Add(@{
                        from    = $fromUpn
                        to      = $toUpn
                        subject = $email.subject
                    })
                    $sent = $true
                    break
                }
                catch {
                    $message = $_.Exception.Message
                    if ($attempt -eq 1 -and $message -match 'DeviceCodeCredential authentication failed') {
                        Write-LabLog -Message "Graph auth failed while sending test data. Reconnecting and retrying once..." -Level Warning
                        Disconnect-MgGraph -ErrorAction SilentlyContinue
                        Connect-MgGraph -TenantId $tenantId -Scopes $scopes -NoWelcome -ErrorAction Stop
                        $context = Get-MgContext
                        if (-not $context -or [string]::IsNullOrWhiteSpace($context.Account)) {
                            throw 'Microsoft Graph reconnection did not produce a usable context during test data send.'
                        }
                        $adminUpn = $context.Account
                        continue
                    }

                    Write-LabLog -Message "Failed to send email from $fromUpn to $toUpn`: $message" -Level Warning
                    if ($message -match 'DeviceCodeCredential authentication failed') {
                        throw "Graph authentication failed during test data send after retry: $message"
                    }
                    break
                }
            }

            if (-not $sent) {
                Write-LabLog -Message "Skipping test email after failure: $($email.subject)" -Level Warning
            }

            Start-Sleep -Seconds 2
        }
    }

    # --- Document creation and upload ---
    $createdDocs = [System.Collections.Generic.List[hashtable]]::new()

    if ($Config.workloads.testData.PSObject.Properties['documents'] -and $Config.workloads.testData.documents) {
        foreach ($doc in $Config.workloads.testData.documents) {
            $ownerUpn = [string]$userPrincipalNameLookup[[string]$doc.owner]
            if ([string]::IsNullOrWhiteSpace($ownerUpn)) {
                Write-LabLog -Message "Document owner not found, skipping: $($doc.owner)" -Level Warning
                continue
            }

            if ($PSCmdlet.ShouldProcess("$($doc.fileName) for $ownerUpn", 'Create and upload document')) {
                try {
                    # Create document content as plain text (Word upload via Graph)
                    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($doc.content)

                    # Upload to user's OneDrive root
                    $uploadUri = "/v1.0/users/$ownerUpn/drive/root:/$($doc.fileName):/content"
                    Invoke-MgGraphRequest -Method PUT `
                        -Uri $uploadUri `
                        -ContentType 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' `
                        -Body $contentBytes `
                        -ErrorAction Stop | Out-Null

                    Write-LabLog -Message "Uploaded document $($doc.fileName) to $ownerUpn OneDrive" -Level Success

                    if (-not [string]::IsNullOrWhiteSpace($doc.label)) {
                        Write-LabLog -Message "Note: Sensitivity label '$($doc.label)' for $($doc.fileName) must be applied via Purview auto-labeling or manually." -Level Info
                    }

                    $createdDocs.Add(@{
                        fileName = $doc.fileName
                        owner    = $ownerUpn
                        label    = $doc.label
                    })
                }
                catch {
                    Write-LabLog -Message "Failed to upload document $($doc.fileName) for $ownerUpn`: $($_.Exception.Message)" -Level Warning
                }

                Start-Sleep -Seconds 2
            }
        }
    }

    return @{
        emails    = $sentEmails.ToArray()
        documents = $createdDocs.ToArray()
    }
}

function Remove-TestData {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest  # Reserved for manifest-based removal
    )

    $null = $Config, $Manifest  # Test data removal is a no-op

    if ($PSCmdlet.ShouldProcess('test emails', 'Skip removal')) {
        Write-LabLog -Message 'Test emails cannot be recalled automatically. Manual cleanup may be required.' -Level Warning
    }
}

Export-ModuleMember -Function @(
    'Send-TestData'
    'Remove-TestData'
)
