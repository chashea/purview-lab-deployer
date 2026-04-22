# Integrated AI Security Lab (GCC)

GCC variant of the Integrated AI Security lab. Same 4-in-1 story (Copilot DLP + Shadow AI + Sentinel + unified eDiscovery/retention/IRM) deployed to Azure Government.

## GCC-Specific Notes

> **Azure Government endpoints:** This lab provisions Azure resources in Azure Government (default `usgovvirginia`). Sign in with `az cloud set --name AzureUSGovernment` before `az login`.

### What's confirmed Available in GCC (Moderate) per MS Learn service descriptions

- **Microsoft 365 Copilot for GCC** — GA since December 2024; Wave 2 in April 2025 (Stream, SharePoint, OneNote, Loop Pages)
- **Purview for M365 Copilot** — April 2025 release added Information Protection, Data Lifecycle Management, Audit, eDiscovery, Communication Compliance for Copilot interactions in GCC
- **DSPM for AI** — Available in GCC (Moderate). Note: GCC-H and DoD have the narrower footnote "Browse to URL policy cannot be created; only supported AI sites" — this restriction doesn't apply to regular GCC
- **Endpoint DLP** — fully available in GCC
- **DLP files (SPO/OneDrive) + email** — available
- **DLP for Teams chat + channels** — available
- **Communication Compliance** (classifiers, Exchange/Teams support, three-preconfigured templates, conflict-of-interest, discrimination) — available
- **Insider Risk Management** (including Risky AI Usage template) — available
- **Data Lifecycle Management + retention policies** — available; AI-Applications retention locations (`MicrosoftCopilotExperiences`, `EnterpriseAIApps`, `OtherAIApps`) follow the Purview-for-Copilot wave
- **Information Barriers** — available
- **Defender for Cloud Apps integration** — available
- **Compliance Manager** (FedRAMP / NIST / GDPR templates) — available

### GCC rollout caveats (verify at deploy time)

- **DLP for Microsoft 365 Copilot and Copilot Chat location** (CopilotExperiences) — part of the April 2025 Purview-for-Copilot wave; the deployer's `AdvancedRule` path for label-based Copilot blocking likely works. The SIT-based Copilot prompt rules are preview even on commercial — GCC lag is expected.
- **Browser Data Security** (inline prompt inspection in Edge for Business) — not explicitly itemized in the GCC service-description table. Module degrades gracefully.
- **Network Data Security** (SASE/SSE integration) — not explicitly itemized in GCC tables.
- **Sentinel data lake tier** — launched commercial July 2025, GCC rollout pending. Plan analytics-tier-only in GCC for now.
- **Sentinel in the Microsoft Defender portal** — separate GCC rollout schedule from commercial. The Azure portal Sentinel experience (`portal.azure.us`) is fully supported.
- **Graph `assignSensitivityLabel`** (auto-labeling test documents at deploy) — explicitly unavailable in US Gov L4 / L5 per MS Learn. On GCC Moderate it may succeed; module logs warnings and falls back to manual portal labeling if it fails.

## Prerequisites

1. Microsoft 365 G5 (GCC) or G5 Compliance add-on
2. Microsoft 365 Copilot for GCC licenses assigned to demo users
3. Azure Government subscription with Owner/Contributor
4. Defender for Endpoint onboarded on at least one test device
5. Azure CLI on Azure Government:
   ```bash
   az cloud set --name AzureUSGovernment
   az login
   az account set --subscription <gcc-subscription-guid>
   ```
6. PowerShell 7+

## Deploy

```powershell
./Deploy-Lab.ps1 -Cloud gcc -LabProfile ai-security `
    -TenantId <gcc-tenant-guid> -SubscriptionId <gcc-subscription-guid>
```

## Scope

- **Config:** `configs/gcc/ai-security-demo.json`
- **Prefix:** `PVAISec`
- **Default region:** `usgovvirginia`

## Deltas from commercial (verified against MS Learn April 2025+ service descriptions)

| Area | Commercial | GCC Moderate (G5) | Notes |
|---|---|---|---|
| Azure cloud | AzureCloud | AzureUSGovernment | `az cloud set --name AzureUSGovernment` |
| Default region | `eastus` | `usgovvirginia` | `usgovarizona` also valid |
| M365 Copilot | GA | **GA since Dec 2024 (Wave 2 April 2025)** | Feature parity for base app |
| Purview for M365 Copilot | GA | **Launched April 2025** (IP, DLM, Audit, eDiscovery, CC) | |
| DSPM for AI | GA | **Available** | GCC-H/DoD has browse-to-URL restriction; GCC Moderate does not |
| Endpoint DLP | GA | **Available** | |
| Insider Risk Management (Risky AI Usage template) | GA | **Available** | |
| Communication Compliance | GA | **Available** | |
| Copilot prompt SIT DLP (preview) | Preview, rolling out | Likely later than commercial — verify | |
| Browser Data Security (Edge for Business inline) | GA | Not itemized in GCC tables — verify | Deployer degrades gracefully |
| Network Data Security (SASE/SSE) | GA | Not itemized in GCC tables — verify | |
| Defender portal unified SecOps | GA; new customers auto-onboard July 2025 | Separate rollout schedule | Azure portal Sentinel still supported |
| Sentinel data lake tier | GA July 2025 | Rollout pending | Plan analytics-tier-only |
| Graph `assignSensitivityLabel` | GA | GCC Moderate: may succeed; GCC-H/DoD: **unavailable** per MS Learn | Module falls back to manual portal labeling |

See the [commercial README](../../commercial/ai-security/README.md), [RUNBOOK](../../commercial/ai-security/RUNBOOK.md), and [talk-track](../../commercial/ai-security/talk-track.md) for the full picture. The same artifact set deploys in GCC — only the Azure endpoints and feature-availability caveats differ.

## Verification

```powershell
./scripts/Test-CopilotDlpReady.ps1 -ConfigPath ./configs/gcc/ai-security-demo.json -Cloud gcc
./scripts/Test-ShadowAiReady.ps1   -ConfigPath ./configs/gcc/ai-security-demo.json -Cloud gcc
./scripts/Test-SentinelReady.ps1   -ConfigPath ./configs/gcc/ai-security-demo.json -Cloud gcc -SubscriptionId <gcc-sub>
```
