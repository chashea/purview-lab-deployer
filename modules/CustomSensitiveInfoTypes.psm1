#Requires -Version 7.0

<#
.SYNOPSIS
    Manages custom sensitive information types for the Purview lab.

.DESCRIPTION
    Creates and removes custom sensitive information types (SITs)
    defined in the lab configuration.
#>

function Deploy-CustomSensitiveInfoTypes {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $createdTypes = [System.Collections.Generic.List[hashtable]]::new()

    # Check if the cmdlet is available in this environment
    $newSitCmd = Get-Command -Name New-DlpSensitiveInformationType -ErrorAction SilentlyContinue
    if (-not $newSitCmd) {
        Write-LabLog -Message 'New-DlpSensitiveInformationType cmdlet unavailable. Custom SITs must be created manually in the Purview portal.' -Level Warning
        return @{ types = @() }
    }

    foreach ($type in $Config.workloads.customSensitiveInfoTypes.types) {
        $name = "$($Config.prefix)-$($type.name)"

        # Check if already exists
        $existing = Get-DlpSensitiveInformationType -Identity $name -ErrorAction SilentlyContinue
        if ($existing) {
            Write-LabLog -Message "Custom SIT already exists: $name" -Level Warning
            $createdTypes.Add(@{
                name   = $name
                status = 'already_exists'
            })
            continue
        }

        if ($PSCmdlet.ShouldProcess($name, 'Create custom sensitive information type')) {
            try {
                New-DlpSensitiveInformationType `
                    -Name $name `
                    -Description $type.description `
                    -ErrorAction Stop | Out-Null

                Write-LabLog -Message "Created custom SIT: $name (pattern: $($type.pattern), confidence: $($type.confidenceLevel))" -Level Success

                $createdTypes.Add(@{
                    name            = $name
                    pattern         = $type.pattern
                    confidenceLevel = $type.confidenceLevel
                    status          = 'created'
                })
            }
            catch {
                Write-LabLog -Message "Failed to create custom SIT '$name': $_" -Level Warning
                $createdTypes.Add(@{
                    name   = $name
                    status = 'failed'
                    error  = $_.ToString()
                })
            }
        }
    }

    return @{
        types = $createdTypes.ToArray()
    }
}

function Remove-CustomSensitiveInfoTypes {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    $removeSitCmd = Get-Command -Name Remove-DlpSensitiveInformationType -ErrorAction SilentlyContinue
    if (-not $removeSitCmd) {
        Write-LabLog -Message 'Remove-DlpSensitiveInformationType cmdlet unavailable. Custom SITs must be removed manually in the Purview portal.' -Level Warning
        return
    }

    # Build target list from manifest or config
    $targetNames = @()

    if ($Manifest) {
        foreach ($entry in @($Manifest.types)) {
            if ($entry -is [string]) {
                $targetNames += [string]$entry
            }
            elseif ($entry.name) {
                $targetNames += [string]$entry.name
            }
        }
    }

    if ($targetNames.Count -eq 0) {
        foreach ($type in $Config.workloads.customSensitiveInfoTypes.types) {
            $targetNames += "$($Config.prefix)-$($type.name)"
        }
    }

    foreach ($name in $targetNames) {
        $existing = Get-DlpSensitiveInformationType -Identity $name -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-LabLog -Message "Custom SIT not found (may already be removed): $name" -Level Warning
            continue
        }

        if ($PSCmdlet.ShouldProcess($name, 'Remove custom sensitive information type')) {
            try {
                Remove-DlpSensitiveInformationType -Identity $name -Confirm:$false -ErrorAction Stop
                Write-LabLog -Message "Removed custom SIT: $name" -Level Success
            }
            catch {
                Write-LabLog -Message "Failed to remove custom SIT '$name': $_" -Level Warning
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Deploy-CustomSensitiveInfoTypes'
    'Remove-CustomSensitiveInfoTypes'
)
