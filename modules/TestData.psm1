#Requires -Version 7.0

<#
.SYNOPSIS
    Test data workload module for purview-lab-deployer.
    Sends test emails via Microsoft Graph to trigger Purview policies.
#>

function Set-LabDriveItemSensitivityLabel {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$OwnerUpn,

        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [string]$LabelIdentity
    )

    if (-not $PSCmdlet.ShouldProcess("$FileName for $OwnerUpn", "Assign sensitivity label '$LabelIdentity'")) {
        return $false
    }

    $labelGuid = Resolve-LabSensitivityLabelGuid -LabelName $LabelIdentity
    if (-not $labelGuid) {
        Write-LabLog -Message "Skipping label assignment for '$FileName' — could not resolve label '$LabelIdentity' to a GUID." -Level Warning
        return $false
    }

    try {
        $encodedName = [uri]::EscapeDataString($FileName)
        $item = Invoke-MgGraphRequest -Method GET `
            -Uri "/v1.0/users/$OwnerUpn/drive/root:/$encodedName" `
            -ErrorAction Stop

        $driveId = [string]$item.parentReference.driveId
        $itemId = [string]$item.id
        if ([string]::IsNullOrWhiteSpace($driveId) -or [string]::IsNullOrWhiteSpace($itemId)) {
            Write-LabLog -Message "Could not resolve drive/item IDs for '$FileName' in $OwnerUpn's drive. Skipping label assignment." -Level Warning
            return $false
        }

        $body = @{
            sensitivityLabelId = $labelGuid
            assignmentMethod   = 'standard'
            justificationText  = 'Purview lab demo seeding'
        }

        Invoke-MgGraphRequest -Method POST `
            -Uri "/v1.0/drives/$driveId/items/$itemId/assignSensitivityLabel" `
            -Body $body `
            -ContentType 'application/json' `
            -ErrorAction Stop | Out-Null

        Write-LabLog -Message "Applied sensitivity label '$LabelIdentity' to '$FileName' ($OwnerUpn)." -Level Success
        return $true
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match '403|Forbidden|NotSupported|not available') {
            Write-LabLog -Message "Cannot apply label to '$FileName' — Graph assignSensitivityLabel is not available in this cloud or the app lacks Files.ReadWrite.All. Apply the label manually in the portal." -Level Warning
        }
        else {
            Write-LabLog -Message "Failed to apply sensitivity label to '$FileName' for $OwnerUpn`: $msg" -Level Warning
        }
        return $false
    }
}

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
        # Default owner (for configs that omit per-document owner): first resolved test user
        $defaultOwnerUpn = if ($userPrincipalNameLookup.Values.Count -gt 0) {
            [string]($userPrincipalNameLookup.Values | Select-Object -First 1)
        }
        else {
            $null
        }

        foreach ($doc in $Config.workloads.testData.documents) {
            $fileName = if ($doc.PSObject.Properties['fileName'] -and -not [string]::IsNullOrWhiteSpace([string]$doc.fileName)) {
                [string]$doc.fileName
            }
            elseif ($doc.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$doc.name)) {
                [string]$doc.name
            }
            else {
                $null
            }
            if ([string]::IsNullOrWhiteSpace($fileName)) {
                Write-LabLog -Message 'Document entry missing fileName/name, skipping.' -Level Warning
                continue
            }

            $ownerUpn = if ($doc.PSObject.Properties['owner'] -and $userPrincipalNameLookup.ContainsKey([string]$doc.owner)) {
                [string]$userPrincipalNameLookup[[string]$doc.owner]
            }
            else {
                $defaultOwnerUpn
            }

            if ([string]::IsNullOrWhiteSpace($ownerUpn)) {
                Write-LabLog -Message "Document owner not resolved for '$fileName', skipping." -Level Warning
                continue
            }

            $labelIdentity = if ($doc.PSObject.Properties['labelIdentity'] -and -not [string]::IsNullOrWhiteSpace([string]$doc.labelIdentity)) {
                [string]$doc.labelIdentity
            }
            elseif ($doc.PSObject.Properties['label'] -and -not [string]::IsNullOrWhiteSpace([string]$doc.label)) {
                [string]$doc.label
            }
            else {
                $null
            }

            if ($PSCmdlet.ShouldProcess("$fileName for $ownerUpn", 'Create and upload document')) {
                try {
                    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($doc.content)
                    $encodedName = [uri]::EscapeDataString($fileName)
                    $uploadUri = "/v1.0/users/$ownerUpn/drive/root:/$encodedName`:/content"
                    Invoke-MgGraphRequest -Method PUT `
                        -Uri $uploadUri `
                        -ContentType 'text/plain' `
                        -Body $contentBytes `
                        -ErrorAction Stop | Out-Null

                    Write-LabLog -Message "Uploaded document $fileName to $ownerUpn OneDrive." -Level Success

                    $appliedLabel = $null
                    if ($labelIdentity) {
                        # Small delay so the drive item is visible before labeling
                        Start-Sleep -Seconds 2
                        if (Set-LabDriveItemSensitivityLabel -OwnerUpn $ownerUpn -FileName $fileName -LabelIdentity $labelIdentity) {
                            $appliedLabel = $labelIdentity
                        }
                    }

                    $createdDocs.Add(@{
                        fileName = $fileName
                        owner    = $ownerUpn
                        label    = $appliedLabel
                    })
                }
                catch {
                    $errMsg = $_.Exception.Message
                    if ($errMsg -match 'mysite not found|NotFound') {
                        Write-LabLog -Message "Skipping document upload '$fileName' for $ownerUpn - OneDrive not provisioned (requires SharePoint license). Assign license and re-run." -Level Warning
                    }
                    else {
                        Write-LabLog -Message "Failed to upload document $fileName for $ownerUpn`: $errMsg" -Level Warning
                    }
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
