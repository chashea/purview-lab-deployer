# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Automated Microsoft Purview demo lab deployment via PowerShell 7+.
Config-driven, modular by workload, deploy + teardown symmetry.
Three deployment profiles: basic-lab, shadow-ai, copilot-dlp — each with commercial and GCC variants.

## Stack

- PowerShell 7+ (pwsh)
- ExchangeOnlineManagement >= 3.0
- Microsoft.Graph SDK (Users, Groups, Authentication)

## Tenants

| Environment | Tenant ID | Domain |
|---|---|---|
| **Commercial** | `f1b92d41-6d54-4102-9dd9-4208451314df` | `MngEnvMCAP648165.onmicrosoft.com` |
| **GCC** | `119e9fe0-c9d3-4a9d-be8b-c82d03fd0cd4` | `MngEnvMCAP659995.onmicrosoft.com` |

## Commands

```powershell
# Deploy (direct)
./Deploy-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -Cloud commercial

# Deploy (profile shorthand — resolves to configs/<cloud>/<profile>-demo.json)
./Deploy-Lab.ps1 -LabProfile basic-lab -Cloud commercial

# Deploy (interactive — prompts for cloud, profile, tenant)
./Deploy-Lab-Interactive.ps1

# Dry run (no cloud connection)
./Deploy-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -SkipAuth -WhatIf

# Teardown (config-based, prefix fallback)
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -Cloud commercial

# Teardown (manifest-based, precise resource IDs)
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -ManifestPath manifests/commercial/PVLab_20260316-152133.json

# Teardown (interactive)
./Remove-Lab-Interactive.ps1

# Lint (CI uses this — zero warnings required)
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns

# Install PSScriptAnalyzer
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```

No Pester test suite. CI validation is PSScriptAnalyzer lint only (`.github/workflows/validate.yml`).

## Architecture

### Orchestration Flow

`Deploy-Lab.ps1` imports all `modules/*.psm1`, loads config JSON, resolves cloud, loads capability profile from `profiles/<cloud>/capabilities.json`, gates unavailable workloads, connects to EXO + Graph, then deploys workloads in dependency order. Each `Deploy-*` function returns manifest data (created resource IDs). Manifest is exported to `manifests/<cloud>/<prefix>_<timestamp>.json` (git-ignored).

`Remove-Lab.ps1` mirrors deploy with reversed workload order. Accepts optional `-ManifestPath` for precise teardown; without it, falls back to config + prefix-based lookup.

### Deployment Order (dependency-driven)

1. Foundry → 2. TestUsers → 3. SensitivityLabels → 4. DLP → 5. Retention → 6. EDiscovery → 7. CommunicationCompliance → 8. InsiderRisk → 9. ConditionalAccess → 10. TestData → 11. AuditConfig

Foundry deploys first so agents exist before Purview policies that govern them. Removal is the exact reverse (Foundry last). TestData removal is a no-op (sent emails cannot be recalled).

### Module Contract

Every workload module in `modules/` exports:
- `Deploy-<Workload> -Config <hashtable> [-WhatIf]` — returns manifest data (array of resource IDs)
- `Remove-<Workload> -Config <hashtable> [-Manifest <hashtable>] [-WhatIf]` — uses manifest for precise removal, falls back to config + prefix

Exceptions: `Prerequisites.psm1` and `Logging.psm1` are utility modules (no Deploy/Remove). `TestData.psm1` exports `Send-TestData` (no removal). All DLP/auto-label rules use built-in Microsoft SITs (e.g., `U.S. Social Security Number (SSN)`, `Credit Card Number`).

### Config Structure

Configs live under `configs/<cloud>/<scenario>.json`. Schema at `configs/_schema.json`. Required fields: `labName`, `prefix`, `domain`. Workloads are toggled via `"enabled": true/false` in the `workloads` object. Each workload section contains its resource definitions (policies, labels, users, etc.).

Shadow AI uses prefix `PVShadowAI`; baseline uses `PVLab`.

### Cloud Environments

Two supported clouds with capability profiles at `profiles/<cloud>/capabilities.json`. Deploy-Lab blocks on `unavailable` workloads and warns on `limited`.

| Environment | SKU Baseline | Endpoints | Notes |
|---|---|---|---|
| **Commercial** | Microsoft 365 E5 | Worldwide Graph + portal | Full feature parity, all workloads available |
| **GCC** | Microsoft 365 G5 (GCC) | Worldwide endpoints (not GCC High/DoD) | Feature rollout cadence differs from commercial |

#### Workload Availability by Cloud

| Workload | Commercial | GCC | GCC Notes |
|---|---|---|---|
| TestUsers | available | available | |
| SensitivityLabels | available | available | |
| DLP | available | available | |
| Retention | available | available | |
| EDiscovery | available | available | |
| CommunicationCompliance | available | limited | Feature parity and DSPM/advanced workflows may differ; validate in tenant first |
| InsiderRisk | available | limited | Capabilities may differ by rollout stage |
| ConditionalAccess | available | available | |
| TestData | available | available | |
| AuditConfig | available | available | |

**Status meanings:** `available` = fully supported, `limited` = functional but feature parity gaps possible, `delayed` = not yet rolled out, `unavailable` = blocked (deploy will refuse).

### DLP Runtime Adaptation

The DLP module (`modules/DLP.psm1`) dynamically detects supported cmdlet parameters at runtime (locations, scoping, label conditions, enforcement actions). This allows the same config to work across different Exchange Online versions with graceful parameter fallback — key complexity to understand before modifying DLP logic.

### Manifest System

Manifests (`manifests/<cloud>/<prefix>_<timestamp>.json`) capture resource GUIDs from each deployment. They are the authoritative source for teardown — prefix-based removal is the fallback. Manifests are git-ignored (contain tenant-specific IDs).

## Conventions

- All resources prefixed with `{config.prefix}-` for reliable teardown
- Idempotent: check existence before creating
- `-WhatIf` support on all deploy/remove functions
- Config files under `configs/commercial/` and `configs/gcc/` only (no root-level configs)
- Cloud resolution order: `-Cloud` param → config file `cloud` field → default `commercial`
- Conditional Access policies deploy in report-only mode (non-blocking)
- Logs written to `logs/` with transcripts (git-ignored)
