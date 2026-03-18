# GCC configuration guide

This folder contains Microsoft Purview lab configs for GCC tenants.

## Primary config

- Baseline full deployment: `full-demo.json`

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid> -Cloud gcc
```

## Shadow AI config

- Shadow AI detection and governance: `shadow-ai-demo.json`

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/gcc/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud gcc
```

See [profiles/gcc/shadow-ai/README.md](../../profiles/gcc/shadow-ai/README.md) for full deployment guide.

## Other configs

- `medical-demo.json`
- `eu-gdpr-demo.json`
- `government-demo.json`
- `education-demo.json`
- `dlp-only.json`
- `ediscovery-retention.json`

## Teardown examples

```powershell
# Config-based removal (full demo)
./Remove-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -TenantId <tenant-guid> -Cloud gcc

# Config-based removal (shadow AI)
./Remove-Lab.ps1 -ConfigPath configs/gcc/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud gcc

# Manifest-based removal
./Remove-Lab.ps1 -ConfigPath configs/gcc/full-demo.json -ManifestPath manifests/gcc/<manifest>.json -TenantId <tenant-guid> -Cloud gcc
```
