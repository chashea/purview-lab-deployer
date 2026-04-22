# Copilot DLP Guardrails Demo

**Tagline:** "We're not turning Copilot off — we're teaching it what it's allowed to see, summarize, and search."

## Scenario Overview

This lab demonstrates how Microsoft Purview DLP enforces data boundaries for Microsoft 365 Copilot and Copilot Chat prompts, files, and AI-driven actions. Customers see what actually happens when those guardrails trigger — and the audit evidence that proves it.

| Component | Count | Details |
|---|---|---|
| Test users | 3 | Megan Torres (Finance), Jordan Kim (Marketing), Nadia Shah (Compliance) |
| Security groups | 2 | Copilot-Users, Compliance-Admins |
| Sensitivity labels | 2 parents, 5 sublabels | Confidential (General, Business Sensitive), Highly Confidential (All Employees, Restricted, Regulated Data) |
| Auto-label policies | 1 | SSN content → Highly Confidential\Regulated Data |
| DLP policies | 2 | Copilot Prompt SIT Block (3 rules), Copilot Labeled Content Block (2 rules) |
| Retention policies | 1 | Copilot interaction retention (365 days) |
| Insider Risk policies | 1 | Risky AI Usage — escalates users who repeatedly trigger Copilot guardrails |
| eDiscovery cases | 1 | Copilot DLP incident review |
| Audit searches | 3 | CopilotInteraction, DlpRuleMatch, DlpRuleUndo |
| Test emails | 4 | Seeded with SSNs, credit cards, Copilot interaction context |
| Test documents | 3 | Financial forecast, employee benefits (SSN), patient intake (PHI) |

## Prerequisites

- Microsoft 365 E5 (or E5 Compliance add-on)
- **Microsoft 365 Copilot** licenses assigned to demo users
- One of these roles: Entra AI Admin, Purview Data Security AI Admin, or Purview Compliance Administrator
- Sensitivity labels published to demo users
- Optional: Preview enrollment for Copilot web search DLP control
- Plan for policy propagation delay: updates can take up to 4 hours to fully reflect in Copilot experiences

## Quick Start

```powershell
# Deploy
./Deploy-Lab.ps1 -Cloud commercial -LabProfile copilot-protection -TenantId <tenant-guid>

# Deploy without test users (use existing tenant accounts)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile copilot-protection -TenantId <tenant-guid> -SkipTestUsers

# Dry run
./Deploy-Lab.ps1 -Cloud commercial -LabProfile copilot-protection -WhatIf

# Teardown
./Remove-Lab.ps1 -Cloud commercial -LabProfile copilot-protection -Confirm:$false -TenantId <tenant-guid>
```

Legacy alias: `copilot-dlp` remains supported for backward compatibility.

## Lab Phases (75–90 minutes, modular)

| Phase | Title | Duration | Automated? |
|---|---|---|---|
| 0 | Baseline — Copilot without guardrails | 5 min | Manual (see RUNBOOK) |
| 1 | Block sensitive prompts (SIT-based, includes web-search protection) | 20 min | Automated (DLP policy, public preview) |
| 2 | Block labeled files from Copilot | 20 min | Automated (DLP policy, GA) |
| 3 | Evidence & investigations | 15 min | Automated (audit + eDiscovery) |

> **Feature status (per Microsoft Learn):** Prompt SIT blocking is in public preview and rolls out per tenant. Label-based file blocking is generally available. The same prompt SIT policy also prevents Copilot from using the sensitive prompt text in internal or web searches — no separate web-search policy is required.

## Post-Deploy Verification

Both SIT-based and label-based DLP rules now deploy end-to-end from PowerShell:

- **SIT rules** use `ContentContainsSensitiveInformation` with `RestrictAccess = ExcludeContentProcessing/Block`.
- **Label rules** use `-AdvancedRule` with resolved sensitivity label GUIDs per MS Learn Example 4.
- **Location** is set via `-Locations` JSON + `-EnforcementPlanes @("CopilotExperiences")`.

After deployment, run the readiness check to confirm the tenant is demo-ready (accounts for the 4-hour propagation window):

```powershell
./scripts/Test-CopilotDlpReady.ps1 -LabProfile copilot-protection -Cloud commercial
```

Exit codes: `0` = ready, `1` = wait (propagating or unpublished labels), `2` = blocked (missing policy, label, or license — action required).

If any item is flagged Blocked:

1. **Missing policy** — run `Deploy-Lab.ps1` again, or check the deployment log in `logs/` for cmdlet errors.
2. **Missing label** — ensure SensitivityLabels workload deployed before DLP; re-run with `-LabProfile copilot-protection`.
3. **Missing Copilot license** — assign `Microsoft_365_Copilot` SKU to the demo users in Entra ID before running the demo.

## Key Technical Notes

- **SIT + label conditions cannot be mixed in the same DLP rule** for Copilot. This lab uses separate policies/rules for each condition type — SIT rules use `ContentContainsSensitiveInformation`, label rules use `-AdvancedRule` with label GUIDs per MS Learn Example 4.
- Prompt SIT controls evaluate text typed directly in prompts. Uploaded file contents in prompts are not DLP-scanned. The same control prevents the sensitive prompt text from being used in internal or external web searches.
- DLP policies deploy in **simulation mode** (TestWithNotifications) by default. Switch to enforce for live demos — and budget another 4h propagation window after the switch.
- DLP updates can take up to 4 hours to fully appear in Copilot and Copilot Chat. Run `./scripts/Test-CopilotDlpReady.ps1` before the demo to confirm readiness.
- DLP for Copilot also covers **prebuilt agents in Microsoft 365 Copilot and Copilot Chat**. Teams Channel Agent has separate considerations.

## References

- [Learn about using Microsoft Purview DLP to protect interactions with Microsoft 365 Copilot and Copilot Chat](https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about)
- [Use Microsoft Purview to manage data security and compliance for Microsoft 365 Copilot and Copilot Chat](https://learn.microsoft.com/purview/ai-m365-copilot)
- [Considerations to manage Microsoft 365 Copilot and Channel Agent in Teams for security and compliance](https://learn.microsoft.com/purview/ai-m365-copilot-considerations)
