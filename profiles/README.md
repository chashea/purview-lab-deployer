# Profiles

This folder contains deployment capability profiles used by `Deploy-Lab.ps1` and `Remove-Lab.ps1`.

## Active cloud profiles

- `commercial/capabilities.json` - commercial tenant workload capabilities
- `gcc/capabilities.json` - GCC tenant workload capabilities

These are selected by the `-Cloud` parameter (`commercial` or `gcc`).

## Canonical lab profiles

### basic

Core compliance lab: OneDrive/Teams/Outlook/SharePoint DLP, sensitivity labels, retention, eDiscovery, insider risk, audit config. Prefix `PVLab`.

- `commercial/basic/README.md` - deployment guide (commercial)
- `gcc/basic/README.md` - deployment guide (GCC)

```powershell
# Commercial
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic -TenantId <tenant-guid>

# GCC
./Deploy-Lab.ps1 -Cloud gcc -LabProfile basic -TenantId <tenant-guid>
```

### ai

Copilot + gen-AI governance: Copilot DLP, Shadow AI detection (Endpoint/Browser/Network), AI-specific labels, IRM, Sentinel integration, cross-signal correlation analytics rules. Prefix `PVAI`. Requires an Azure subscription.

- `commercial/ai/README.md` - deployment guide (commercial)
- `gcc/ai/README.md` - deployment guide (GCC)

```powershell
# Commercial
./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai -TenantId <tenant-guid>

# GCC
./Deploy-Lab.ps1 -Cloud gcc -LabProfile ai -TenantId <tenant-guid>
```

### purview-sentinel

Standalone Purview → Sentinel integration: Log Analytics workspace, Defender XDR + IRM + Office 365 data connectors, analytics rules, workbook, IRM auto-triage playbook. Requires an Azure subscription.

- `commercial/purview-sentinel/README.md` - deployment guide (commercial)

```powershell
./Deploy-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel -TenantId <tenant-guid>
```

## Deprecated aliases

The following names are still accepted and emit a `Write-Warning` at runtime:

| Deprecated | Resolves to |
|------------|-------------|
| `basic-lab` | `basic` |
| `shadow-ai` | `ai` |
| `copilot-dlp` | `ai` |
| `copilot-protection` | `ai` |
| `ai-security` | `ai` |
