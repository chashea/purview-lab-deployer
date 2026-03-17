---
name: deploy-purview-lab
description: Deploy or dry-run the Purview demo lab using repository scripts, cloud profiles, and workload compatibility checks. Use for deploy requests, config-driven setup, and WhatIf validation.
---

Use this skill when the task is to deploy lab resources, validate a config, or troubleshoot deploy flow.

## Procedure

1. Pick cloud/config explicitly.
   - Commercial default config: `configs/commercial/full-demo.json`
   - GCC default config: `configs/gcc/full-demo.json`
   - Resolve cloud using `-Cloud` first, then config `cloud`, then default (`commercial`).

2. Run dry-run first when making changes:
   ```powershell
   ./Deploy-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -Cloud commercial -SkipAuth -WhatIf
   ```
   Use non-`SkipAuth` only when tenant auth is required and available.

3. For authenticated deploys, pass tenant explicitly or use env var:
   ```powershell
   $env:PURVIEW_TENANT_ID = '<tenant-guid>'
   ./Deploy-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -Cloud commercial -TenantId $env:PURVIEW_TENANT_ID
   ```

4. Expect deploy order to remain:
   `testUsers -> sensitivityLabels -> dlp -> retention -> eDiscovery -> communicationCompliance -> insiderRisk -> testData`

5. Validate outputs after successful deploy:
   - Manifest file under `manifests/<cloud>/<prefix>_<timestamp>.json`
   - Log transcript under `logs/`

## Repository-specific guardrails

- Do not bypass capability gating from `profiles/<cloud>/capabilities.json`; deploy must block workloads marked `unavailable`.
- Keep `SupportsShouldProcess` / `-WhatIf` behavior intact.
- Preserve module import pattern from `Deploy-Lab.ps1` (`modules/*.psm1`).
