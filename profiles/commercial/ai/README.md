# Integrated AI Security Lab (Commercial)

One unified deployment covering the full AI security story: **Copilot DLP guardrails + Shadow AI prevention + Sentinel signal integration**, all correlated and signal-feeding into a single SIEM pane.

> **When to use this lab:** when the customer wants the *complete* Microsoft AI security picture in one demo. For focused demos aimed at a single audience (only Copilot, only Shadow AI, only SIEM), use the individual profiles — they ship a tighter story.

## What makes this the "integrated" lab

This lab isn't just the sum of the three focused labs. The signals from each surface **correlate**:

1. **Copilot DLP block** → `SecurityAlert` via Defender XDR → Sentinel `PVAISec-CopilotDLPPromptBlock` rule
2. **Shadow AI paste attempt** → `SecurityAlert` via Endpoint DLP → Sentinel `PVAISec-ShadowAIPasteUpload` rule
3. **Risky AI Usage IRM score rises** → `SecurityAlert` via OfficeIRM connector → Sentinel `PVAISec-IRMHighSev` rule
4. **Same user with BOTH Copilot DLP blocks AND Risky AI IRM scoring** → Sentinel `PVAISec-RiskyAIUsageCorrel` cross-table rule → elevated incident
5. **Adaptive Protection loop**: Sentinel incidents escalate the user's IRM risk score → the DLP policies here are tiered by `insiderRiskLevel` → enforcement *tightens automatically* for repeat offenders

The whole cycle is visible in the `PVAISec-AI Risk Signals` Sentinel workbook.

## Prerequisites

1. **Microsoft 365 E5** (or E5 Compliance add-on)
2. **Microsoft 365 Copilot** licenses for demo users
3. **Azure subscription** with Owner/Contributor
4. **Microsoft Defender for Endpoint** on at least one test device (for live paste/upload demos)
5. **Azure CLI** signed in (`az login`)
6. **PowerShell 7+**

## Deploy

```powershell
az login
az account set --subscription <subscription-guid>

./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai-security `
    -TenantId <tenant-guid> -SubscriptionId <subscription-guid>
```

Deploy time: ~20-25 minutes. Propagation: allow 4 hours for DLP policies + 60 min for Sentinel connector data flow before demoing.

### Optional variations

```powershell
# Dry run (no cloud mutations)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai-security -WhatIf

# Use your own test accounts
./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai-security `
    -TenantId <tenant> -SubscriptionId <sub> -SkipTestUsers

# Teardown (non-destructive; Azure resources preserved)
./Remove-Lab.ps1 -Cloud commercial -LabProfile ai-security `
    -ManifestPath ./manifests/commercial/PVAISec_<timestamp>.json `
    -SubscriptionId <subscription-guid>

# Teardown including Azure resource group (safety-gated — see RUNBOOK)
./Remove-Lab.ps1 -Cloud commercial -LabProfile ai-security `
    -ManifestPath ./manifests/commercial/PVAISec_<timestamp>.json `
    -SubscriptionId <subscription-guid> -ForceDeleteResourceGroup
```

### Post-deploy readiness

```powershell
# Covers Copilot DLP + Shadow AI readiness
./scripts/Test-CopilotDlpReady.ps1 -ConfigPath ./configs/commercial/ai-security-demo.json -Cloud commercial
./scripts/Test-ShadowAiReady.ps1   -ConfigPath ./configs/commercial/ai-security-demo.json -Cloud commercial

# Sentinel readiness
./scripts/Test-SentinelReady.ps1 -ConfigPath ./configs/commercial/ai-security-demo.json -Cloud commercial -SubscriptionId <sub>

# Apply Endpoint DLP browser restrictions (Shadow AI paste/upload blocks)
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -ConfigPath ./configs/commercial/ai-security-demo.json -Apply
```

## Scope

- **Config:** `configs/commercial/ai-security-demo.json`
- **Prefix:** `PVAISec` (all resources)
- **Cloud:** commercial
- **Lifecycle:** fully independent from the focused labs — can coexist with them or replace them

## What gets deployed

### Identity
- 5 test users (`rtorres`, `mchen`, `nbrooks`, `dokafor`, `sreeves`)
- 3 security groups: `PVAISec-AI-Governance`, `PVAISec-Privileged-Data-Owners`, `PVAISec-Business-Users`

### Sensitivity labels
- 2 parents × 5 AI-specific sublabels each: All Employees, AI Internal Use, AI Restricted Recipients, AI Blocked from External Tools, AI Regulated Data
- 2 auto-label policies (SSN → Highly Confidential regulated; Credit Card/Bank Account/IBAN/IP → Confidential regulated)

### DLP — 5 policies covering the full AI surface
| Policy | Location | Purpose |
|---|---|---|
| Copilot Prompt SIT Block | CopilotExperiences | Block SSN/CC/PHI in Copilot prompts (preview) |
| Copilot Labeled Content Block | CopilotExperiences | Block Copilot from labeled restricted/regulated files (GA) |
| Shadow AI - Endpoint Protection | Devices | Block paste/upload to external AI sites via Defender for Endpoint |
| Shadow AI - Browser Prompt Protection | Browser | Inline block on sensitive text in AI prompts in Edge |
| Shadow AI - Network AI Traffic | Network | SASE/SSE-layer block for non-Edge browsers |

All use **risk-tiered enforcement** (Elevated=block, Moderate=warn, Minor=audit) driven by Insider Risk scores.

### Insider Risk — 3 policies
- Risky AI usage (Copilot prompt injection, protected material access)
- Data leaks (DLP-correlated exfiltration signals on AI surfaces)
- Data theft by departing users (AI-specific)

### Retention — 5 policies
Exchange + SharePoint + OneDrive (1y review, 3y evidence) plus AI-specific `MicrosoftCopilotExperiences`, `EnterpriseAIApps`, `OtherAIApps` locations.

### Sentinel integration — 7 analytics rules
1. HighSevDLP (general DLP)
2. IRMHighSev (Insider Risk high severity)
3. LabelDowngrade (sensitivity label downgrade)
4. MassDownloadAfterDLP (cross-table correlation)
5. **CopilotDLPPromptBlock** — AI-specific
6. **ShadowAIPasteUpload** — AI-specific
7. **RiskyAIUsageCorrel** — cross-signal user correlation

Plus the **Microsoft Purview Content Hub solution** (adds MS-maintained analytics rules and `PurviewDataSensitivityLogs` queries), 2 workbooks (`Purview Signals`, `AI Risk Signals`), and the IRM auto-triage Logic App playbook.

### Communication Compliance
- AI Activity Collection (review queue)
- AI Conversation PII/PHI Detection

### eDiscovery
- Unified `AI-Security-Incident-Review` case with broad AI-related hold and search queries

### Conditional Access (report-only)
- Block AI apps for high sign-in risk
- Require MFA on AI app access

### Test data
- 4 seed emails that cross-reference Copilot blocks, Shadow AI attempts, and policy explanations
- 5 OneDrive documents auto-labeled at deploy via Graph `assignSensitivityLabel`

## Demo format

**Length:** 45-75 minutes hands-on, ~30 minutes narrative-only.

See `talk-track.md` for the full presenter script. Structure:

1. Opening + why integrated (2 min)
2. Discovery — what's happening today (3 min)
3. Copilot DLP (sanctioned AI guardrails) (5-10 min)
4. Shadow AI (unsanctioned AI prevention) (10-15 min)
5. Insider Risk — the adaptive bridge (5 min)
6. Sentinel — the unified SIEM pane + cross-signal correlation (10-15 min)
7. Investigation + teardown (5 min)
8. DSPM for AI (optional follow-up, 5 min)

## References

- [MS Learn: DLP for Microsoft 365 Copilot](https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about)
- [MS Learn: Shadow AI deployment guide](https://learn.microsoft.com/purview/deploymentmodels/depmod-data-leak-shadow-ai-step3)
- [MS Learn: Sentinel + Purview integration](https://learn.microsoft.com/azure/sentinel/purview-solution)
- [MS Learn: DSPM for AI](https://learn.microsoft.com/purview/dspm-for-ai)
- [MS Learn: Microsoft Sentinel in the Microsoft Defender portal](https://learn.microsoft.com/azure/sentinel/microsoft-sentinel-defender-portal)

## Validation

- Pester tests (`Invoke-Pester tests/`) cover config shape across all three sub-stories
- Deploy runs DLP preflight + Copilot license preflight
- Three readiness scripts cover their respective surfaces (Copilot DLP, Shadow AI, Sentinel)
- `Test-SentinelLab.ps1` is the deep end-to-end smoke test
