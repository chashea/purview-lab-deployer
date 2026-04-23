# Copilot Instructions — purview-lab-deployer

## Build, test, and lint commands

- No compile/build step. No Pester test suite.
- CI validation is PowerShell linting via `PSScriptAnalyzer` (`.github/workflows/validate.yml`).

```powershell
# Install lint dependency (same tool used in CI)
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser

# Full lint (matches CI behavior/rules)
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns

# Single-file lint
Invoke-ScriptAnalyzer -Path ./Deploy-Lab.ps1 -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
```

Optional smoke checks without connecting to cloud services:

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/basic-demo.json -Cloud commercial -SkipAuth -WhatIf
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-demo.json -Cloud commercial -SkipAuth -WhatIf
```

## Repository layout

```
root/
├── Deploy-Lab.ps1, Remove-Lab.ps1       # Main orchestrators
├── Deploy-Lab-Interactive.ps1            # Interactive deploy wrapper
├── Remove-Lab-Interactive.ps1            # Interactive remove wrapper
├── configs/
│   ├── _schema.json                      # Canonical JSON schema
│   ├── commercial/                       # Commercial tenant configs
│   │   ├── basic-demo.json, ai-demo.json, purview-sentinel-demo.json, dlp-only.json, ...
│   │   └── README.md
│   └── gcc/                              # GCC tenant configs
│       ├── basic-demo.json, dlp-only.json, ...
│       └── README.md
├── modules/                              # Workload modules (*.psm1)
├── profiles/
│   ├── commercial/
│   │   ├── capabilities.json             # Commercial workload capabilities
│   │   ├── basic/                        # Basic lab scenario profile + guide
│   │   ├── ai/                           # Integrated AI governance profile (Copilot DLP + Shadow AI + Sentinel) + runbook + demo
│   │   └── purview-sentinel/             # Sentinel SOC profile + guide
│   ├── gcc/
│   │   ├── capabilities.json             # GCC workload capabilities
│   │   ├── basic/                        # Basic lab scenario profile + guide
│   │   ├── ai/                           # Integrated AI governance profile (GCC variant)
│   │   └── purview-sentinel/             # Sentinel SOC profile (GCC variant)
│   └── README.md
├── scripts/                              # Helper scripts
├── manifests/                            # Deploy manifests (gitignored)
├── logs/                                 # Transcripts (gitignored)
└── tasks/                                # Dev-internal tracking
```

## High-level architecture

- `Deploy-Lab.ps1` is the main deploy orchestrator:
  - imports all `modules/*.psm1`
  - loads config via `Import-LabConfig`
  - resolves cloud via `Resolve-LabCloud` (`commercial`/`gcc`)
  - loads capability metadata from `profiles/<cloud>/capabilities.json`
  - blocks deploy when enabled workloads are marked `unavailable`
  - runs DLP preflight checks for enforcement config compatibility
  - runs workloads in dependency order and exports a manifest to `manifests/<cloud>/<prefix>_<timestamp>.json`
  - runs post-deploy DLP validation

- `Remove-Lab.ps1` is the teardown orchestrator:
  - same config/cloud/profile resolution path
  - optional `-ManifestPath` enables precise removal from manifest data
  - without manifest, falls back to config + prefix-based removal
  - removes in reverse dependency order; `TestData` is intentionally a no-op for removal

- Interactive wrappers collect cloud/tenant/config input and call the non-interactive orchestrators.

- Core shared infrastructure:
  - `modules/Prerequisites.psm1`: prerequisites, auth, config, cloud profile, workload compatibility, manifest I/O
  - `modules/Logging.psm1`: transcript-backed structured logging into `logs/`
  - workload modules (`DLP`, `SensitivityLabels`, `Retention`, `EDiscovery`, `CommunicationCompliance`, `InsiderRisk`, `ConditionalAccess`, `TestUsers`, `TestData`, `AuditConfig`)

- Error isolation via `Invoke-Workload` wrapper:
  - failure in one workload does not halt deployment
  - manifest is built with partial data from successful workloads
  - summary of successes/failures logged at end

- Authentication flow (handled by `Prerequisites.psm1`):
  - `Connect-ExchangeOnline` for compliance cmdlets (DLP, retention, eDiscovery, etc.)
  - `Connect-MgGraph` for Entra ID operations (users, groups, conditional access)
  - Required modules: `ExchangeOnlineManagement >= 3.0`, `Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, `Microsoft.Graph.Groups`, `Microsoft.Graph.Identity.SignIns`
  - Required Entra ID roles: Compliance Administrator, User Administrator, eDiscovery Administrator

## Deployment tracks

- **Basic lab** (baseline): `configs/<cloud>/basic-demo.json` — core compliance workloads, prefix `PVLab`. `-LabProfile basic`.
- **AI governance** (integrated): `configs/<cloud>/ai-demo.json` — Copilot DLP + Shadow AI (Endpoint/Browser/Network) + Sentinel + cross-signal analytics, prefix `PVAI`. `-LabProfile ai`. Has a manual demo runbook at `profiles/commercial/ai/RUNBOOK.md`. Requires an Azure subscription.
- **Sentinel SOC**: `configs/<cloud>/purview-sentinel-demo.json` — Sentinel workspace + Purview connectors + analytics + IRM auto-triage playbook, prefix `PVSentinel`. `-LabProfile purview-sentinel`. Requires an Azure subscription.
- **Scenario configs**: `dlp-only.json`, `ediscovery-retention.json`, `education-demo.json`, `eu-gdpr-demo.json`, `government-demo.json`, `medical-demo.json` — narrower overlays, deploy via `-ConfigPath`.

The three canonical profiles are independent tracks with separate prefixes and lifecycles.

## Key conventions

- Workload module contract:
  - each workload module exposes paired `Deploy-<Workload>` and `Remove-<Workload>` functions
  - deploy receives `-Config` and `-WhatIf`
  - remove receives `-Config`, `-Manifest` (when relevant), and `-WhatIf`

- Config and cloud conventions:
  - config files are cloud-scoped under `configs/commercial/` and `configs/gcc/`
  - no root-level config files (removed during reorg)
  - cloud resolution order: `-Cloud` param → config `cloud` field → `$env:PURVIEW_CLOUD` → default `commercial`
  - `PURVIEW_TENANT_ID` and `PURVIEW_CLOUD` are first-class runtime inputs

- Naming/teardown strategy:
  - resources are consistently prefix-based (`{config.prefix}-...`) to support fallback cleanup
  - manifests are the authoritative source for precise teardown when available

- Compatibility gating:
  - workload support status (`available`, `limited`, `delayed`, `unavailable`) is data-driven from capability profiles
  - deploy treats `unavailable` as a blocker; remove treats it as warning context

- DLP runtime adaptation (`modules/DLP.psm1`):
  - optional `policyMode`, `enforcement`, `appliesToGroups`, and `labels` fields in config
  - dynamically detects supported cmdlet parameters at runtime to handle EXO version differences:
    - locations: `ExchangeLocation` vs `ExchangeSenderMemberOf` vs `UserScope`
    - enforcement: `BlockAccess` vs `Mode` vs `EnforcementMode`
    - labels: `SensitivityLabels` vs `Labels`
    - overrides: `AllowOverrideWithJustification` vs `AllowOverride` vs `UserCanOverride`
  - unsupported params degrade gracefully to audit mode with warnings
  - this is the most complex module — read the detection logic before modifying DLP functions

## Git and release workflow

- Always `git push` changes to `origin main` after committing.
- After pushing, update GitHub Releases with notes from the commit(s).
- Small commits (bug fixes, config tweaks, doc updates) increment the **minor** version (e.g., v0.32.0 → v0.33.0).
- **Major** version bumps are reserved for creating or removing a solution/project.
- Use `gh release create` with a tag and release notes summarizing the changes.
