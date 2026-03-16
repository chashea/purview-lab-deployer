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
    $adminUpn = $context.Account

    $sentEmails = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($email in $Config.workloads.testData.emails) {
        $fromUpn = "$($email.from)@$($Config.domain)"
        $toUpn = "$($email.to)@$($Config.domain)"

        if ($PSCmdlet.ShouldProcess("Send email to $toUpn (on behalf of $fromUpn)`: $($email.subject)")) {
            try {
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

                Invoke-MgGraphRequest -Method POST `
                    -Uri "/v1.0/users/$adminUpn/sendMail" `
                    -Body $body

                Write-LabLog -Message "Sent email from $fromUpn to $toUpn`: $($email.subject)" -Level Success

                $sentEmails.Add(@{
                    from    = $fromUpn
                    to      = $toUpn
                    subject = $email.subject
                })
            }
            catch {
                Write-LabLog -Message "Failed to send email from $fromUpn to $toUpn`: $($_.Exception.Message)" -Level Warning
            }

            Start-Sleep -Seconds 2
        }
    }

    return @{
        emails = $sentEmails.ToArray()
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
