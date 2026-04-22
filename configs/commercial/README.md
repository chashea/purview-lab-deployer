# Commercial configuration guide

This folder contains Microsoft Purview lab configs for commercial tenants.

## Primary configs

Each canonical profile has a single config:

- `basic-demo.json` — baseline compliance lab (DLP, labels, retention, eDiscovery, insider risk, audit config). Prefix `PVLab`.
- `ai-demo.json` — AI governance lab (Copilot DLP, Shadow AI, Sentinel, IRM). Prefix `PVAI`.
- `purview-sentinel-demo.json` — standalone Sentinel integration lab.

```powershell
./Deploy-Lab.ps1 -LabProfile basic -Cloud commercial -TenantId <tenant-guid>
./Deploy-Lab.ps1 -LabProfile ai    -Cloud commercial -TenantId <tenant-guid>
```

## Using your own test users

Each config ships with pre-licensed demo users. To run the same profile against a different set of existing tenant users, pass `-TestUsers`:

```powershell
./Deploy-Lab.ps1 -LabProfile basic -Cloud commercial -TestUsers alice@contoso.com,bob@contoso.com
./Deploy-Lab.ps1 -LabProfile ai    -Cloud commercial -TestUsers alice@contoso.com,bob@contoso.com
```

When `-TestUsers` is supplied, the config's `testUsers.users` list is replaced with the provided UPNs, groups are cleared, and the mode is forced to `existing` (no user creation).

## Other configs

- `medical-demo.json`
- `eu-gdpr-demo.json`
- `government-demo.json`
- `education-demo.json`
- `dlp-only.json`
- `ediscovery-retention.json`

## Teardown examples

```powershell
# Config-based removal
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-demo.json -TenantId <tenant-guid> -Cloud commercial

# Manifest-based removal
./Remove-Lab.ps1 -ConfigPath configs/commercial/basic-demo.json -ManifestPath manifests/commercial/<manifest>.json -TenantId <tenant-guid> -Cloud commercial
```
