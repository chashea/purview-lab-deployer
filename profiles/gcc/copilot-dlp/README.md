# Copilot DLP Guardrails Demo (GCC)

**Tagline:** "We're not turning Copilot off — we're teaching it what it's allowed to see, summarize, and search."

## GCC-Specific Notes

> **Licensing:** This lab requires **Microsoft 365 G5** (or G5 Compliance add-on) and **Copilot for Microsoft 365** in GCC.
>
> **Feature parity:** DLP for Copilot and Copilot audit events may have delayed rollout in GCC compared to commercial. Validate availability in your tenant before deploying. The deployer gracefully degrades if `CopilotLocation` is not yet available — DLP policies will log a warning and skip the Copilot location.
>
> **GCC Limitation — No SIT-Based Copilot DLP:** In GCC, you cannot create a DLP policy targeting Microsoft 365 Copilot with Sensitive Information Type (SIT) conditions in the rules. Only label-based rules are supported for Copilot DLP in GCC. This lab deploys label-based content blocking only.
>
> **Copilot availability:** Confirm Microsoft 365 Copilot is available and licensed in your GCC tenant. GCC feature rollout may lag behind commercial by weeks to months.

## Scenario Overview

This lab demonstrates how Microsoft Purview DLP enforces data boundaries for Microsoft 365 Copilot and Copilot Chat prompts, files, and AI-driven actions in a GCC environment. Customers see what actually happens when those guardrails trigger — and the audit evidence that proves it.

| Component | Count | Details |
|---|---|---|
| Test users | 3 | Megan Torres (Finance), Jordan Kim (Marketing), Nadia Shah (Compliance) |
| Security groups | 2 | Copilot-Users, Compliance-Admins |
| Sensitivity labels | 2 parents, 5 sublabels | Confidential (General, Business Sensitive), Highly Confidential (All Employees, Restricted, Regulated Data) |
| Auto-label policies | 1 | SSN content → Highly Confidential\Regulated Data |
| DLP policies | 1 | Copilot Labeled Content Block (2 rules) |
| Retention policies | 1 | Copilot interaction retention (365 days) |
| eDiscovery cases | 1 | Copilot DLP incident review |
| Audit searches | 3 | CopilotInteraction, DlpRuleMatch, DlpRuleUndo |
| Test emails | 4 | Seeded with SSNs, credit cards, Copilot interaction context |
| Test documents | 3 | Financial forecast, employee benefits (SSN), patient intake (PHI) |

## Prerequisites

- **Microsoft 365 G5** (or G5 Compliance add-on)
- **Microsoft 365 Copilot** licenses assigned to demo users (GCC availability required)
- One of these roles: Entra AI Admin, Purview Data Security AI Admin, or Purview Compliance Administrator
- Sensitivity labels published to demo users
- Validate `CopilotLocation` parameter availability: run `Get-Command New-DlpCompliancePolicy` and check for `CopilotLocation` in parameters
- For web-search scenarios, explicitly configure **Allow web search in Copilot** (GCC default is off)
- Plan for policy propagation delay: updates can take up to 4 hours to fully reflect in Copilot experiences

## Quick Start

```powershell
# Deploy
./Deploy-Lab.ps1 -Cloud gcc -LabProfile copilot-protection -TenantId <tenant-guid>

# Deploy without test users (use existing tenant accounts)
./Deploy-Lab.ps1 -Cloud gcc -LabProfile copilot-protection -TenantId <tenant-guid> -SkipTestUsers

# Dry run
./Deploy-Lab.ps1 -Cloud gcc -LabProfile copilot-protection -WhatIf

# Teardown
./Remove-Lab.ps1 -Cloud gcc -LabProfile copilot-protection -Confirm:$false -TenantId <tenant-guid>
```

Legacy alias: `copilot-dlp` remains supported for backward compatibility.

## Pre-Deploy Validation (GCC)

Before deploying, confirm Copilot DLP support in your GCC tenant:

```powershell
# Connect to Security & Compliance PowerShell
Connect-IPPSSession

# Check if CopilotLocation parameter is available
(Get-Command New-DlpCompliancePolicy).Parameters.Keys | Where-Object { $_ -like '*Copilot*' }

# Expected output: CopilotLocation
# If empty: Copilot DLP location is not yet available in this GCC tenant
```

If `CopilotLocation` is not available, the deployer will skip the Copilot location with a warning. DLP policies will be created without the Copilot scope — you can add the location manually in the portal when the feature rolls out.

## Lab Phases (90–120 minutes, modular)

| Phase | Title | Duration | Automated? |
|---|---|---|---|
| 0 | Baseline — Copilot without guardrails | 5 min | Manual (see RUNBOOK) |
| 1 | Block labeled files from Copilot | 20 min | Automated (DLP policy) |
| 2 | Stop Copilot web search with sensitive data | 15 min | Manual/Preview (see RUNBOOK) |
| 3 | Evidence & investigations | 15 min | Automated (audit + eDiscovery) |

## Key Technical Notes

- **GCC supports label-based Copilot DLP only.** SIT-based conditions (sensitive info types in prompts) are not supported for Copilot DLP rules in GCC. This lab deploys a single policy with two label-based rules.
- DLP policies deploy in **simulation mode** (TestWithNotifications) by default. Switch to enforce for live demos.
- Prompt SIT controls evaluate typed prompt text only. Uploaded file contents in prompts are not DLP-scanned.
- DLP updates can take up to 4 hours to fully appear in Copilot and Copilot Chat.
- Phase 2 (web search prevention) requires **Private Preview** enrollment — may not be available in GCC.
- GCC web search defaults to disabled unless enabled with Cloud Policy (**Allow web search in Copilot**).
- **GCC rollout lag:** If Copilot DLP features are not yet available in your GCC tenant, the deployer degrades gracefully. Use the RUNBOOK to identify which features require manual portal configuration.

## References

- [Learn about using Microsoft Purview DLP to protect interactions with Microsoft 365 Copilot and Copilot Chat](https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about)
- [Use Microsoft Purview to manage data security and compliance for Microsoft 365 Copilot and Copilot Chat](https://learn.microsoft.com/purview/ai-m365-copilot)
- [Data, privacy, and security for web search in Microsoft 365 Copilot and Copilot Chat](https://learn.microsoft.com/microsoft-365/copilot/manage-public-web-access#web-search)
- [Considerations to manage Microsoft 365 Copilot and Channel Agent in Teams for security and compliance](https://learn.microsoft.com/purview/ai-m365-copilot-considerations)
- [Microsoft 365 feature availability in GCC](https://learn.microsoft.com/office365/servicedescriptions/office-365-platform-service-description/office-365-us-government/gcc)
