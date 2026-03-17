---
name: remove-purview-lab
description: Tear down Purview lab resources safely using Remove-Lab.ps1, including manifest-based precise removal and prefix-based fallback cleanup. Covers full-demo and Shadow AI teardown.
---

Use this skill when asked to remove lab resources or troubleshoot teardown.

## Procedure

1. Prefer manifest-based removal when available:
   ```powershell
   ./Remove-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -Cloud commercial -ManifestPath manifests/commercial/<manifest>.json -TenantId <tenant-guid>
   ```

2. If manifest is unavailable, use config + prefix fallback:
   ```powershell
   ./Remove-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -Cloud commercial -TenantId <tenant-guid>
   ```

3. Shadow AI teardown (separate from baseline):
   ```powershell
   ./Remove-Lab.ps1 -ConfigPath configs/commercial/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud commercial -Confirm:$false
   ```
   This only removes `PVShadowAI-*` resources. Baseline `PVLab-*` resources are untouched.

4. Use dry-run before destructive changes:
   ```powershell
   ./Remove-Lab.ps1 -ConfigPath configs/commercial/full-demo.json -Cloud commercial -SkipAuth -WhatIf
   ```

5. Keep reverse teardown order intact:
   `insiderRisk -> communicationCompliance -> eDiscovery -> retention -> dlp -> sensitivityLabels -> testUsers`
   (`testData` is logged as non-removable/no-op).

## Repository-specific guardrails

- Maintain optional `-ManifestPath` semantics: precise removal when present, prefix fallback when absent.
- Keep cloud compatibility warnings for remove context (`Test-LabWorkloadCompatibility -Operation Remove`).
- Preserve `SupportsShouldProcess`/confirmation semantics in `Remove-Lab.ps1`.
- DLP rule/policy not-found exceptions during removal are treated as warnings, not hard failures.
