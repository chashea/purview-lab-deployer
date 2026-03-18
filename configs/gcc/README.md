# GCC configuration guide

This folder contains Microsoft Purview lab configs for GCC tenants.

## Primary config

- Baseline lab deployment: `basic-lab-demo.json`

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/gcc/basic-lab-demo.json -TenantId <tenant-guid> -Cloud gcc
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
./Remove-Lab.ps1 -ConfigPath configs/gcc/basic-lab-demo.json -TenantId <tenant-guid> -Cloud gcc

# Manifest-based removal
./Remove-Lab.ps1 -ConfigPath configs/gcc/basic-lab-demo.json -ManifestPath manifests/gcc/<manifest>.json -TenantId <tenant-guid> -Cloud gcc
```
