# purview-lab-deployer

Automated Microsoft Purview demo lab deployment via PowerShell 7+. Config-driven, modular by workload, with deploy + teardown symmetry.

## What It Does

Automates the entire Purview demo environment setup:
- **Test Users & Groups** — creates demo users with departments/roles via Microsoft Graph
- **DLP Policies** — US PII, financial data protection rules
- **Sensitivity Labels** — parent/sublabels with encryption, content marking, label publication policy, and auto-label policies
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

### Interactive deploy (prompts for cloud + tenant)

```powershell
./Deploy-Lab-Interactive.ps1
```

### Interactive teardown (prompts for cloud + tenant + optional manifest)

```powershell
./Remove-Lab-Interactive.ps1
```

### Commercial (E5-style) deploy

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -TenantId <tenant-guid>
```

`full-demo.json` is now the baseline Purview deployment and does **not** include Shadow AI controls.

### Shadow AI deployment recap (separate deployment)

Deploy Shadow AI controls with the dedicated config:

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud commercial
```

The dedicated `shadow-ai-demo.json` deployment includes:
- Shadow AI demo users and governance groups
- Shadow AI-focused DLP policies and rules
- AI-focused sensitivity sublabels and auto-label policy
- Shadow AI retention policies
- Shadow AI eDiscovery case (`Shadow-AI-Incident-Review`)
- Shadow AI Communication Compliance monitoring policy
- Insider Risk `Risky AI usage` policy
- Seeded Shadow AI test emails

Recommended validation after deploy:
- Confirm deployment summary includes all workloads and no error-skipped workloads
- Confirm post-deploy validation passes in `Deploy-Lab.ps1`
- Review generated manifest under `manifests/commercial/`

To remove only Shadow AI resources:

```powershell
./Remove-Lab.ps1 -ConfigPath configs/commercial/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud commercial -Confirm:$false
```

### GCC (G5) deploy

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid>
```

### GCC (G5) label publish only

```powershell
./Publish-Labels-GCC.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid>
```

### Dry run (WhatIf)

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid> -WhatIf
```

### Deploy only DLP workloads

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/dlp-only.json -TenantId <tenant-guid>
```

### Teardown

```powershell
# Using config (prefix-based removal)
./Remove-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -TenantId <tenant-guid>

# Using manifest (precise removal)
./Remove-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -ManifestPath manifests/gcc/PVLab_20260316-100000.json -TenantId <tenant-guid>

# Skip confirmation prompt
./Remove-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -TenantId <tenant-guid> -Confirm:$false
```

Set `PURVIEW_TENANT_ID` to avoid passing `-TenantId` on every command:

```powershell
$env:PURVIEW_TENANT_ID = '<tenant-guid>'
```

Set `PURVIEW_CLOUD` (or pass `-Cloud`) to force cloud profile selection:

```powershell
$env:PURVIEW_CLOUD = 'gcc'  # or 'commercial'
./Deploy-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid> -Cloud gcc
```

## Commercial E5 vs GCC G5 behavior

- GCC profile targets GCC (not GCC High/DoD).
- GCC uses worldwide endpoints (`portal.azure.com`, `graph.microsoft.com`), but feature parity/release cadence can differ.
- Capability metadata is data-driven via `profiles/commercial/capabilities.json` and `profiles/gcc/capabilities.json`.
- Deploy preflight warns for workloads marked `limited` or `delayed`, and blocks workloads marked `unavailable`.

## Config Files

| Config | Commercial | GCC |
|---|---|---|
| `full-demo.json` | `configs/commercial/full-demo.json` | `configs/gcc/full-demo.json` |
| `medical-demo.json` | `configs/commercial/medical-demo.json` | `configs/gcc/medical-demo.json` |
| `eu-gdpr-demo.json` | `configs/commercial/eu-gdpr-demo.json` | `configs/gcc/eu-gdpr-demo.json` |
| `government-demo.json` | `configs/commercial/government-demo.json` | `configs/gcc/government-demo.json` |
| `education-demo.json` | `configs/commercial/education-demo.json` | `configs/gcc/education-demo.json` |
| `shadow-ai-demo.json` | `configs/commercial/shadow-ai-demo.json` | `—` (commercial-only) |
| `dlp-only.json` | `configs/commercial/dlp-only.json` | `configs/gcc/dlp-only.json` |
| `ediscovery-retention.json` | `configs/commercial/ediscovery-retention.json` | `configs/gcc/ediscovery-retention.json` |

### Custom configs

Copy from the appropriate cloud folder and modify. Each workload has an `enabled: true/false` toggle. All resources are prefixed with the config's `prefix` value (default: `PVLab`).

## Architecture

```
Deploy-Lab.ps1          # Orchestrator (deploy in dependency order)
Deploy-Lab-Interactive.ps1 # Prompted deploy wrapper (cloud + tenant)
Publish-Labels-GCC.ps1  # GCC-only label publication runner
Remove-Lab.ps1          # Orchestrator (teardown in reverse order)
Remove-Lab-Interactive.ps1 # Prompted teardown wrapper (cloud + tenant + manifest)
modules/
  Prerequisites.psm1    # Auth, config loading, cloud profile + manifest I/O
  Logging.psm1          # Structured logging with transcript
  TestUsers.psm1        # Users + groups via Graph SDK
  DLP.psm1              # DLP policies + rules
  SensitivityLabels.psm1 # Labels, sublabels, auto-labeling
  Retention.psm1        # Retention policies + rules
  EDiscovery.psm1       # Cases, holds, searches
  CommunicationCompliance.psm1 # Supervisory review
  InsiderRisk.psm1      # IRM via Graph beta API
  TestData.psm1         # Seed emails with sensitive content
profiles/
  commercial/capabilities.json # Commercial E5 baseline workload support
  gcc/capabilities.json        # GCC G5 workload support + caveats
configs/
  _schema.json                 # Config validation schema
  commercial/*.json            # Commercial cloud configs
  gcc/*.json                   # GCC cloud configs
manifests/
  commercial/                  # Commercial deploy manifests
  gcc/                         # GCC deploy manifests
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
