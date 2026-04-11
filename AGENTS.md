# AGENTS.md

This file provides guidance to AI coding agents (Codex, Jules, OpenCode, Copilot CLI) working in this repository.

## Project Overview

Automated Microsoft Purview demo lab deployment via PowerShell 7+.
Config-driven, modular by workload, deploy + teardown symmetry.
Three deployment profiles: basic-lab, shadow-ai, copilot-dlp — each with commercial and GCC variants.

## Stack

- PowerShell 7+ (pwsh)
- ExchangeOnlineManagement >= 3.0
- Microsoft.Graph SDK (Users, Groups, Authentication)

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

1. TestUsers → 2. SensitivityLabels → 3. DLP → 4. Retention → 5. EDiscovery → 6. CommunicationCompliance → 7. InsiderRisk → 8. ConditionalAccess → 9. TestData → 10. AuditConfig

Removal is the exact reverse. TestData removal is a no-op.

### Module Contract

Every workload module in `modules/` exports:
- `Deploy-<Workload> -Config <hashtable> [-WhatIf]` — returns manifest data
- `Remove-<Workload> -Config <hashtable> [-Manifest <hashtable>] [-WhatIf]` — uses manifest for precise removal, falls back to prefix

Exceptions: `Prerequisites.psm1` and `Logging.psm1` are utility modules. `TestData.psm1` exports `Send-TestData` only.

For AI Foundry agent security, see [chashea/ai-agent-security](https://github.com/chashea/ai-agent-security).

## Conventions

- All resources prefixed with `{config.prefix}-` for reliable teardown
- Idempotent: check existence before creating
- `-WhatIf` support on all deploy/remove functions
- Config files under `configs/commercial/` and `configs/gcc/` only
- Cloud resolution: `-Cloud` param → config `cloud` field → `$env:PURVIEW_CLOUD` → default `commercial`
- Conditional Access policies deploy in report-only mode
- DLP module dynamically detects supported cmdlet parameters at runtime for cross-version compatibility
