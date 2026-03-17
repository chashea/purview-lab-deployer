# GCC configuration guide

This folder contains Microsoft Purview lab configs for GCC tenants.

## Primary config

- Baseline full deployment: `full-demo.json`

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid> -Cloud gcc
```

## Other configs

- `medical-demo.json`
- `eu-gdpr-demo.json`
- `government-demo.json`
- `education-demo.json`
- `dlp-only.json`
- `ediscovery-retention.json`

## GCC label publication helper

```powershell
./scripts/Publish-Labels-GCC.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid>
```

## Teardown examples

```powershell
# Config-based removal
./Remove-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid> -Cloud gcc

# Manifest-based removal
./Remove-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -ManifestPath manifests/gcc/<manifest>.json -TenantId <tenant-guid> -Cloud gcc
```
