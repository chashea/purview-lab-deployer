# Commercial configuration guide

This folder contains Microsoft Purview lab configs for commercial tenants.

## Primary config

- Baseline lab deployment: `basic-lab-demo.json`

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -TenantId <tenant-guid> -Cloud commercial
```

## Existing-user configs

Use these configs when test users are already licensed in the tenant. Skips user creation, references existing UPNs, and enables test data delivery.

- `basic-lab-existing-demo.json` — Full basic-lab workloads with existing licensed users
- `shadow-ai-existing-demo.json` — Full shadow-ai workloads remapped to existing licensed users
- `existing-users-demo.json` — Minimal config (DLP + labels + eDiscovery + test data)

```powershell
# Deploy basic-lab with existing users
./Deploy-Lab.ps1 -LabProfile basic-lab-existing -Cloud commercial

# Deploy shadow-ai with existing users
./Deploy-Lab.ps1 -LabProfile shadow-ai-existing -Cloud commercial
```

## Other configs

- `medical-demo.json`
- `eu-gdpr-demo.json`
- `government-demo.json`
- `education-demo.json`
- `dlp-only.json`
- `ediscovery-retention.json`
- `shadow-ai-demo.json` (commercial-only Shadow AI track)

## Shadow AI (separate deployment)

Shadow AI is intentionally separate from `basic-lab-demo.json`.

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud commercial
./Remove-Lab.ps1 -ConfigPath configs/commercial/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud commercial -Confirm:$false
```

More details: `../../profiles/commercial/shadow-ai/README.md`

## Teardown examples

```powershell
# Config-based removal
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -TenantId <tenant-guid> -Cloud commercial

# Manifest-based removal
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -ManifestPath manifests/commercial/<manifest>.json -TenantId <tenant-guid> -Cloud commercial
```
