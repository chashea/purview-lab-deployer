# Commercial configuration guide

This folder contains Microsoft Purview lab configs for commercial tenants.

## Primary configs

Each profile has a single canonical config:

- `basic-lab-demo.json` — baseline lab (DLP, labels, retention, eDiscovery, insider risk)
- `shadow-ai-demo.json` — shadow AI detection and governance
- `copilot-dlp-demo.json` — Copilot DLP guardrails

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/basic-lab-demo.json -TenantId <tenant-guid> -Cloud commercial
```

## Using your own test users

Each config ships with a set of pre-licensed demo users baked in. To run the same profile against a different set of existing tenant users, pass `-TestUsers`:

```powershell
./Deploy-Lab.ps1 -LabProfile basic-lab -Cloud commercial -TestUsers alice@contoso.com,bob@contoso.com
./Deploy-Lab.ps1 -LabProfile shadow-ai -Cloud commercial -TestUsers alice@contoso.com,bob@contoso.com
```

When `-TestUsers` is supplied, the config's `testUsers.users` list is replaced with the provided UPNs, groups are cleared, and the mode is forced to `existing` (no user creation). When omitted, the users already listed in the config are used as-is.

## Other configs

- `medical-demo.json`
- `eu-gdpr-demo.json`
- `government-demo.json`
- `education-demo.json`
- `dlp-only.json`
- `ediscovery-retention.json`

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
