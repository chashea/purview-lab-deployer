# Copilot Instructions — purview-lab-deployer

## Build, test, and lint commands

- This repository does not have a compile/build step and does not currently include a Pester test suite.
- CI validation is PowerShell linting via `PSScriptAnalyzer` (`.github/workflows/validate.yml`).

```powershell
# Install lint dependency (same tool used in CI)
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser

# Full lint (matches CI behavior/rules)
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns

# Single-file lint (use this instead of "single test")
Invoke-ScriptAnalyzer -Path ./Deploy-Lab.ps1 -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
```

Optional smoke checks for orchestration logic without connecting to cloud services:

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -Cloud commercial -SkipAuth -WhatIf
./Remove-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -Cloud commercial -SkipAuth -WhatIf
```

## High-level architecture

- `Deploy-Lab.ps1` is the main deploy orchestrator:
  - imports all `modules/*.psm1`
  - loads config via `Import-LabConfig`
  - resolves cloud via `Resolve-LabCloud` (`commercial`/`gcc`)
  - loads capability metadata from `profiles/<cloud>/capabilities.json`
  - blocks deploy when enabled workloads are marked `unavailable`
  - runs workloads in dependency order and exports a manifest to `manifests/<cloud>/<prefix>_<timestamp>.json`

- `Remove-Lab.ps1` is the teardown orchestrator:
  - same config/cloud/profile resolution path
  - optional `-ManifestPath` enables precise removal from manifest data
  - without manifest, falls back to config + prefix-based removal
  - removes in reverse dependency order; `TestData` is intentionally a no-op for removal

- Interactive wrappers (`Deploy-Lab-Interactive.ps1`, `Remove-Lab-Interactive.ps1`) collect cloud/tenant/config input and call the non-interactive orchestrators.

- Core shared infrastructure:
  - `modules/Prerequisites.psm1`: prerequisites, auth, config, cloud profile, workload compatibility, manifest I/O
  - `modules/Logging.psm1`: transcript-backed structured logging into `logs/`
  - workload modules (`DLP`, `SensitivityLabels`, `Retention`, `EDiscovery`, `CommunicationCompliance`, `InsiderRisk`, `TestUsers`, `TestData`)

## Key conventions in this codebase

- Workload module contract:
  - each workload module exposes paired `Deploy-<Workload>` and `Remove-<Workload>` functions
  - deploy receives `-Config` and `-WhatIf`
  - remove receives `-Config`, `-Manifest` (when relevant), and `-WhatIf`

- Config and cloud conventions:
  - config files are cloud-scoped under `configs/commercial` and `configs/gcc`
  - cloud can come from `-Cloud`, config `cloud`, or defaults to `commercial`
  - `PURVIEW_TENANT_ID` and `PURVIEW_CLOUD` are first-class runtime inputs used by orchestrators/wrappers

- Naming/teardown strategy:
  - resources are consistently prefix-based (`{config.prefix}-...`) to support fallback cleanup
  - manifests are the authoritative source for precise teardown when available

- Compatibility gating:
  - workload support status (`available`, `limited`, `delayed`, `unavailable`) is data-driven from capability profiles
  - deploy treats `unavailable` as a blocker; remove treats it as warning context
