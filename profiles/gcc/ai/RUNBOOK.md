# Integrated AI Governance Lab — Post-Deploy Runbook (GCC)

GCC variant. See the [commercial RUNBOOK](../../commercial/ai/RUNBOOK.md) for the full flow; this document captures GCC-specific deltas.

## GCC prerequisites

```bash
az cloud set --name AzureUSGovernment
az login
az account set --subscription <gcc-subscription-guid>
```

## GCC-specific readiness check

```powershell
./scripts/Test-CopilotDlpReady.ps1 -ConfigPath ./configs/gcc/ai-demo.json -Cloud gcc
./scripts/Test-ShadowAiReady.ps1   -ConfigPath ./configs/gcc/ai-demo.json -Cloud gcc
./scripts/Test-SentinelReady.ps1   -ConfigPath ./configs/gcc/ai-demo.json -Cloud gcc -SubscriptionId <gcc-sub>
```

## Feature availability map

Validate each of these in your GCC tenant before demoing:

| Feature | Where to check |
|---|---|
| Copilot prompt SIT DLP | Purview portal → DLP → Create policy → location picker includes Microsoft 365 Copilot and Copilot Chat |
| Label-based Copilot DLP | Same — GA |
| Endpoint DLP | Purview → DLP settings → Endpoint DLP settings should be available |
| Microsoft Sentinel | portal.azure.us → Microsoft Sentinel |
| Sentinel Defender portal | security.microsoft.com → check if Microsoft Sentinel node is available for your tenant |
| Sentinel data lake tier | Defender portal → Sentinel → Settings → Tables → tier toggle |
| DSPM for AI | Purview portal → Solutions |
| Microsoft Purview Content Hub solution | Sentinel → Content Hub → search "Microsoft Purview" |
| IRM Risky AI Usage template | Purview → Insider Risk → Policies → templates list |
| Graph `assignSensitivityLabel` | Runs at deploy time via TestData.psm1; check deploy log for 403/NotSupported warnings |

## Commercial RUNBOOK sections that apply identically

1. Push Endpoint DLP browser restrictions (section 2)
2. Defender XDR connector consent (section 3)
3. Insider Risk SIEM export (section 4) — if IRM is available in your GCC tenant
4. Device onboarding for Shadow AI demos (section 5)
5. Microsoft Purview Content Hub solution (section 7)
6. Seed signals before live demo (section 8)
7. Teardown safety gates (section 10)

## GCC-specific considerations

### Sentinel in the Azure portal

Use `portal.azure.us` (not `portal.azure.com`). Defender portal availability in GCC depends on your tenant's rollout stage.

### Microsoft Sentinel data lake

Commercial GA July 2025. GCC rollout pending. Plan for analytics-tier-only configuration until data lake lights up in your GCC tenant.

### DSPM for AI

Commercial GA. GCC rollout varies. When available, activation follows the same flow as commercial RUNBOOK section 6.

### Graph assignSensitivityLabel

Per MS Learn, this API is explicitly unavailable in US Gov L4 and L5 (GCC High and DoD). For GCC Moderate, it may still succeed — check the deploy log. If labels don't auto-apply, label the files manually via OneDrive web UI for the demo.

## GCC verification checklist

- [ ] Azure CLI is on AzureUSGovernment cloud (`az cloud show` confirms)
- [ ] Resource group deployed to `usgovvirginia` (or configured GCC region)
- [ ] Sentinel workspace visible at `portal.azure.us`
- [ ] Defender XDR connector consented (or noted as pending rollout)
- [ ] IRM availability validated per-tenant
- [ ] Copilot prompt SIT DLP validated per-tenant (will deploy regardless; enforcement depends on feature rollout)
- [ ] Test documents auto-labeled (or manually labeled if Graph API declined)
- [ ] At least one device onboarded to Defender for Endpoint
- [ ] Analytics rules enabled
- [ ] Seed signals generated
- [ ] Workbooks rendered
