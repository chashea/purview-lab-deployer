# GCC configuration guide

This folder contains Microsoft Purview lab configs for GCC tenants.

## Primary configs

- `basic-demo.json` — baseline compliance lab (DLP, labels, retention, eDiscovery, insider risk, audit config). Prefix `PVLab`.
- `ai-demo.json` — AI governance lab (Copilot DLP label-only, Shadow AI, IRM). Prefix `PVAI`.

> **GCC note:** SIT-based Copilot prompt blocking is commercial-only. The GCC `ai` profile uses label-based Copilot DLP only. Shadow AI (Endpoint DLP) and IRM are available.

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/gcc/basic-demo.json -TenantId <tenant-guid> -Cloud gcc
./Deploy-Lab.ps1 -LabProfile basic -Cloud gcc -TenantId <tenant-guid>
./Deploy-Lab.ps1 -LabProfile ai    -Cloud gcc -TenantId <tenant-guid>
```

## Other configs

- `medical-demo.json`
- `eu-gdpr-demo.json`
- `government-demo.json`
- `education-demo.json`
- `dlp-only.json`
- `ediscovery-retention.json`

## Teardown examples

```powershell
# Config-based removal (basic lab)
./Remove-Lab.ps1 -ConfigPath configs/gcc/basic-demo.json -TenantId <tenant-guid> -Cloud gcc

# Manifest-based removal
./Remove-Lab.ps1 -ConfigPath configs/gcc/basic-demo.json -ManifestPath manifests/gcc/<manifest>.json -TenantId <tenant-guid> -Cloud gcc
```
