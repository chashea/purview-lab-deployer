---
applyTo: "modules/**"
---

# Workload Module Rules

- Every workload module exports paired `Deploy-<Workload>` and `Remove-<Workload>` functions via `Export-ModuleMember`.
- Deploy receives `-Config <hashtable>` and supports `-WhatIf` via `[CmdletBinding(SupportsShouldProcess)]`.
- Remove receives `-Config <hashtable>`, optional `-Manifest <hashtable>`, and `-WhatIf`.
- Check existence before creating resources (idempotent). Use `-ErrorAction SilentlyContinue` on Get-* calls.
- All resource names use `"$($Config.prefix)-$($resourceDef.name)"` pattern.
- Gate destructive operations with `$PSCmdlet.ShouldProcess()`.
- Use `Write-LabLog` from `Logging.psm1` for structured output (Info, Warning, Error levels).
- `DLP.psm1` dynamically detects supported cmdlet parameters at runtime — read the detection logic before modifying.
- Exceptions: `Prerequisites.psm1` and `Logging.psm1` are utility modules (no Deploy/Remove). `TestData.psm1` exports `Send-TestData` with no removal.
