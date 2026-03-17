---
name: update-workload-modules
description: Add or modify Purview workload modules while preserving deploy/remove symmetry, orchestrator ordering, and cloud capability metadata.
---

Use this skill for workload feature work in `modules/*.psm1` and related config/profile changes.

## Required implementation pattern

1. Keep workload module symmetry:
   - `Deploy-<Workload>` function
   - `Remove-<Workload>` function
   - `Export-ModuleMember` includes both

2. Keep parameter contract:
   - Deploy receives `-Config` and `-WhatIf`
   - Remove receives `-Config`, optional `-Manifest`, and `-WhatIf`

3. Wire orchestrators explicitly:
   - Add deploy invocation to `Deploy-Lab.ps1` in dependency order
   - Add remove invocation to `Remove-Lab.ps1` in reverse order
   - Respect `<workload>.enabled` toggles from config

4. Update cloud capability metadata:
   - `profiles/commercial/capabilities.json`
   - `profiles/gcc/capabilities.json`
   - Shadow AI scenario profiles: `profiles/<cloud>/shadow-ai/capabilities.json`
   - Use statuses: `available`, `limited`, `delayed`, `unavailable`

5. If workload config shape changes, update cloud-scoped config files under:
   - `configs/commercial/*.json`
   - `configs/gcc/*.json`
   - Shadow AI config: `configs/commercial/shadow-ai-demo.json`

6. Helper scripts go in `scripts/` (not the repo root).

## Validation checklist

- `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns`
- Dry-run deploy/remove with `-SkipAuth -WhatIf` against a representative config.
