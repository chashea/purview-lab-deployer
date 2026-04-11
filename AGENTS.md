# AGENTS.md

This file provides guidance to AI coding agents (Codex, Jules, OpenCode, Copilot CLI) working in this repository.

## Project Overview

Automated Microsoft Purview demo lab deployment via PowerShell 7+.
Config-driven, modular by workload, deploy + teardown symmetry.
Four deployment profiles: basic-lab, shadow-ai, copilot-dlp, foundry — each with commercial and GCC variants.

## Stack

- PowerShell 7+ (pwsh)
- ExchangeOnlineManagement >= 3.0
- Microsoft.Graph SDK (Users, Groups, Authentication)
- Az.Accounts (for Azure AI Foundry resource provisioning)

## Commands

```powershell
# Deploy (direct)
./Deploy-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -Cloud commercial

# Dry run (no cloud connection)
./Deploy-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -SkipAuth -WhatIf

# Teardown (manifest-based, precise)
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -ManifestPath manifests/commercial/PVLab_<timestamp>.json

# Teardown (config-based fallback)
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -Cloud commercial

# Lint (CI uses this — zero warnings required)
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns

# Single-file lint
Invoke-ScriptAnalyzer -Path ./Deploy-Lab.ps1 -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
```

```powershell
# Run Pester tests
Invoke-Pester tests/ -Output Detailed
```

CI runs PSScriptAnalyzer lint, Pester tests, and a smoke test (module import + config load).

## Architecture

`Deploy-Lab.ps1` imports all `modules/*.psm1`, loads config JSON, resolves cloud, loads capability profile from `profiles/<cloud>/capabilities.json`, gates unavailable workloads, connects to EXO + Graph, then deploys workloads in dependency order. Manifest exported to `manifests/<cloud>/<prefix>_<timestamp>.json`.

`Remove-Lab.ps1` mirrors deploy with reversed workload order. Optional `-ManifestPath` for precise teardown; without it, falls back to config + prefix-based lookup.

### Deployment Order

1. Foundry → 2. TestUsers → 3. SensitivityLabels → 4. DLP → 5. Retention → 6. EDiscovery → 7. CommunicationCompliance → 8. InsiderRisk → 9. ConditionalAccess → 10. TestData → 11. AuditConfig

Removal is the exact reverse (Foundry last). TestData removal is a no-op.

### Module Contract

Every workload module in `modules/` exports:
- `Deploy-<Workload> -Config <hashtable> [-WhatIf]` — returns manifest data
- `Remove-<Workload> -Config <hashtable> [-Manifest <hashtable>] [-WhatIf]` — uses manifest for precise removal, falls back to prefix

Exceptions: `Prerequisites.psm1` and `Logging.psm1` are utility modules. `TestData.psm1` exports `Send-TestData` only.

`Foundry.psm1` exports `Deploy-Foundry` and `Remove-Foundry`. Internally organized as: ARM operations (resource provisioning), agent packaging (Teams manifest and ZIP), and public API entry points.

## Conventions

- All resources prefixed with `{config.prefix}-` for reliable teardown
- Idempotent: check existence before creating
- `-WhatIf` support on all deploy/remove functions
- Config files under `configs/commercial/` and `configs/gcc/` only
- Cloud resolution: `-Cloud` param → config `cloud` field → `$env:PURVIEW_CLOUD` → default `commercial`
- Conditional Access policies deploy in report-only mode
- DLP module dynamically detects supported cmdlet parameters at runtime for cross-version compatibility
