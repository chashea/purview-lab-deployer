# purview-lab-deployer

Automated Microsoft Purview demo lab deployment via PowerShell 7+. Config-driven, modular by workload, with deploy + teardown symmetry.

## What It Does

Automates the entire Purview demo environment setup:
- **Test Users & Groups** — creates demo users with departments/roles via Microsoft Graph
- **DLP Policies** — US PII, financial data protection rules
- **Sensitivity Labels** — parent/sublabels with encryption and content marking, auto-label policies
- **Retention Policies** — configurable retention periods and actions
- **eDiscovery** — cases, legal holds, compliance searches
- **Communication Compliance** — supervisory review policies
- **Insider Risk Management** — policies via Graph beta API with priority user groups
- **Test Data** — sends emails containing sensitive content patterns (SSN, credit cards, etc.)

## Prerequisites

- **PowerShell 7+** (`pwsh`)
- **Modules:**
  - `ExchangeOnlineManagement` >= 3.0
  - `Microsoft.Graph.Authentication`
  - `Microsoft.Graph.Users`
  - `Microsoft.Graph.Groups`
- **Admin Roles:** Compliance Administrator, User Administrator, eDiscovery Administrator
- **Graph Permissions:** `User.ReadWrite.All`, `Group.ReadWrite.All`, `Mail.Send`

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
```

## Usage

### Deploy a full demo lab

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/full-demo.json
```

### Dry run (WhatIf)

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/full-demo.json -WhatIf
```

### Deploy only DLP workloads

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/dlp-only.json
```

### Teardown

```powershell
# Using config (prefix-based removal)
./Remove-Lab.ps1 -ConfigPath configs/full-demo.json

# Using manifest (precise removal)
./Remove-Lab.ps1 -ConfigPath configs/full-demo.json -ManifestPath manifests/PVLab_20260316-100000.json

# Skip confirmation prompt
./Remove-Lab.ps1 -ConfigPath configs/full-demo.json -Confirm:$false
```

## Config Files

| Config | Description |
|---|---|
| `full-demo.json` | All workloads enabled — complete Purview demo |
| `dlp-only.json` | DLP policies + test users + test data |
| `ediscovery-retention.json` | eDiscovery cases + retention policies |

### Custom configs

Copy any config and modify. Each workload has an `enabled: true/false` toggle. All resources are prefixed with the config's `prefix` value (default: `PVLab`).

## Architecture

```
Deploy-Lab.ps1          # Orchestrator (deploy in dependency order)
Remove-Lab.ps1          # Orchestrator (teardown in reverse order)
modules/
  Prerequisites.psm1    # Auth, config loading, manifest I/O
  Logging.psm1          # Structured logging with transcript
  TestUsers.psm1        # Users + groups via Graph SDK
  DLP.psm1              # DLP policies + rules
  SensitivityLabels.psm1 # Labels, sublabels, auto-labeling
  Retention.psm1        # Retention policies + rules
  EDiscovery.psm1       # Cases, holds, searches
  CommunicationCompliance.psm1 # Supervisory review
  InsiderRisk.psm1      # IRM via Graph beta API
  TestData.psm1         # Seed emails with sensitive content
configs/
  full-demo.json        # All workloads
  dlp-only.json         # DLP-focused
  ediscovery-retention.json # eDiscovery + retention
  _schema.json          # Config validation schema
```

## Design Principles

1. **Prefix-based naming** — every resource gets `{prefix}-` prefix for reliable identification and teardown
2. **Idempotent** — checks if resources exist before creating; safe to re-run
3. **Deployment manifest** — writes JSON manifest after deploy for precise teardown
4. **WhatIf support** — dry-run mode validates config without creating anything
5. **Dependency ordering** — deploy: Users -> Labels -> DLP -> Retention -> eDiscovery -> CommCompliance -> IRM -> TestData; teardown: reverse

## Lint

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost
```
