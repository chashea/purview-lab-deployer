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

    $types = @()

    if (-not $Config.workloads.customSensitiveInfoTypes.types) {
        return @{ types = $types }
    }

    Write-LabLog -Message 'Custom Sensitive Info Types require manual creation in the Purview portal (Data classification > Classifiers > Sensitive info types > Create).' -Level Warning

    if ($PSCmdlet.ShouldProcess('Custom SITs', 'Log manual creation guidance')) {
        foreach ($type in $Config.workloads.customSensitiveInfoTypes.types) {
        $typeName = "$($Config.prefix)-$($type.name)"
        Write-LabLog -Message "Custom SIT to create manually: '$typeName' — Pattern: $($type.pattern) — Confidence: $($type.confidenceLevel)" -Level Info
        $types += @{
            name            = $typeName
            pattern         = $type.pattern
            confidenceLevel = $type.confidenceLevel
            status          = 'manual-required'
        }
    }
    }

    return @{ types = $types }
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
