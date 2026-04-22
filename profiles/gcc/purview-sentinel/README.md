# Purview → Sentinel Integration Lab (GCC)

GCC variant of the Purview → Sentinel integration. Mirror of the commercial profile with Azure Government endpoints and GCC-specific feature caveats.

## GCC-Specific Notes

> **Azure Government endpoints:** This lab provisions Azure resources in Azure Government (e.g., `usgovvirginia`, `usgovarizona`). Sign in with `az cloud set --name AzureUSGovernment` before `az login`.
>
> **Sentinel Defender portal availability:** GCC rollout is on a separate schedule from commercial. Validate before relying on the Defender portal experience in this demo. The Azure portal Sentinel experience is fully supported in GCC today.
>
> **IRM feature parity:** Microsoft 365 Insider Risk Management feature rollout in GCC can lag commercial by weeks to months. Validate the SIEM export toggle and `OfficeIRM` connector availability in your GCC tenant.
>
> **Data lake tier:** Microsoft Sentinel data lake availability in GCC may lag commercial (launched commercial in July 2025). Check current status before configuring table tiers.

## Prerequisites

1. **Microsoft 365 G5** (GCC) or G5 Compliance add-on
2. **Azure Government subscription** with Owner/Contributor
3. **Azure CLI with AzureUSGovernment cloud set**:
   ```bash
   az cloud set --name AzureUSGovernment
   az login
   az account set --subscription <gcc-subscription-guid>
   ```
4. **PowerShell 7+**
5. **Insider Risk SIEM export** enabled in Purview (if IRM is GA in your GCC tenant)
6. **Defender XDR tenant admin consent** on the connector

## Deploy

```powershell
./Deploy-Lab.ps1 -Cloud gcc -LabProfile purview-sentinel `
    -TenantId <gcc-tenant-guid> -SubscriptionId <gcc-subscription-guid>
```

## Scope

- **Config:** `configs/gcc/purview-sentinel-demo.json`
- **Prefix:** `PVSentinel`
- **Default region:** `usgovvirginia` (change in config if needed)

## Deltas from commercial

| Area | Commercial | GCC |
|---|---|---|
| Azure cloud | AzureCloud | AzureUSGovernment |
| Default region | `eastus` | `usgovvirginia` |
| Portal | Azure + Defender (recommended) | Azure (Defender rollout pending) |
| Data lake tier | GA July 2025 | Rollout pending |
| IRM connector | GA | Availability varies by tenant |

See the commercial profile's [README](../../commercial/purview-sentinel/README.md), [RUNBOOK](../../commercial/purview-sentinel/RUNBOOK.md), and [talk-track](../../commercial/purview-sentinel/talk-track.md) for the full deployment details. The same artifact set deploys in GCC — only the endpoints and cloud context change.

## Verification

```powershell
./scripts/Test-SentinelReady.ps1 -LabProfile purview-sentinel -Cloud gcc `
    -SubscriptionId <gcc-subscription-guid>
```
