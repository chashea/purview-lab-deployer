---
name: remove-purview-lab
description: Tear down Purview lab resources safely using Remove-Lab.ps1, including manifest-based precise removal and prefix-based fallback cleanup. Covers all three canonical profiles (basic, ai, purview-sentinel).
---

Use this skill when asked to remove lab resources or troubleshoot teardown.

## Procedure

1. Prefer manifest-based removal when available:
   ```powershell
   ./Remove-Lab.ps1 -LabProfile basic -Cloud commercial -ManifestPath manifests/commercial/<manifest>.json -TenantId <tenant-guid>
   ```

2. If manifest is unavailable, use config + prefix fallback:
   ```powershell
   ./Remove-Lab.ps1 -LabProfile basic -Cloud commercial -TenantId <tenant-guid>
   ```

3. `ai` profile teardown (separate from baseline):
   ```powershell
   ./Remove-Lab.ps1 -LabProfile ai -TenantId <tenant-guid> -Cloud commercial -Confirm:$false
   ```
   This only removes `PVAI-*` resources. Baseline `PVLab-*` resources are untouched. Pass `-ForceDeleteResourceGroup` (with a manifest) if you want the Sentinel resource group deleted too.

4. Use dry-run before destructive changes:
   ```powershell
   ./Remove-Lab.ps1 -LabProfile basic -Cloud commercial -SkipAuth -WhatIf
   ```

5. Keep reverse teardown order intact:
   `sentinelIntegration -> auditConfig -> conditionalAccess -> insiderRisk -> communicationCompliance -> eDiscovery -> retention -> dlp -> sensitivityLabels -> testUsers`
   (`testData` is logged as non-removable/no-op — sent emails cannot be recalled.)

## Repository-specific guardrails

- Maintain optional `-ManifestPath` semantics: precise removal when present, prefix fallback when absent.
- Keep cloud compatibility warnings for remove context (`Test-LabWorkloadCompatibility -Operation Remove`).
- Preserve `SupportsShouldProcess`/confirmation semantics in `Remove-Lab.ps1`.
- DLP rule/policy not-found exceptions during removal are treated as warnings, not hard failures.
- Sentinel resource group deletion is safety-gated: `-ForceDeleteResourceGroup` requires manifest + `createdBy=purview-lab-deployer` tag + name match.
