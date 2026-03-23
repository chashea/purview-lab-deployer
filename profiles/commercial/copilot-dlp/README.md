# Copilot DLP Guardrails Demo

**Tagline:** "We're not turning Copilot off — we're teaching it what it's allowed to see, summarize, and search."

## Scenario Overview

This lab demonstrates how Microsoft Purview DLP enforces data boundaries for Microsoft 365 Copilot prompts, files, and AI-driven actions. Customers see what actually happens when those guardrails trigger — and the audit evidence that proves it.

| Component | Count | Details |
|---|---|---|
| Test users | 3 | Megan Torres (Finance), Jordan Kim (Marketing), Nadia Shah (Compliance) |
| Security groups | 2 | Copilot-Users, Compliance-Admins |
| Sensitivity labels | 2 parents, 5 sublabels | Confidential (General, Business Sensitive), Highly Confidential (All Employees, Restricted, Regulated Data) |
| Auto-label policies | 1 | SSN content → Highly Confidential\Regulated Data |
| DLP policies | 2 | Copilot Prompt SIT Block (3 rules), Copilot Labeled Content Block (2 rules) |
| Retention policies | 1 | Copilot interaction retention (365 days) |
| eDiscovery cases | 1 | Copilot DLP incident review |
| Audit searches | 3 | CopilotInteraction, DlpRuleMatch, DlpRuleUndo |
| Test emails | 4 | Seeded with SSNs, credit cards, Copilot interaction context |
| Test documents | 3 | Financial forecast, employee benefits (SSN), patient intake (PHI) |

## Prerequisites

- Microsoft 365 E5 (or E5 Compliance add-on)
- **Microsoft 365 Copilot** licenses assigned to demo users
- Purview DLP permissions (Compliance Administrator or Data Security AI Admin)
- Sensitivity labels published to demo users
- Optional: Preview enrollment for Copilot web search DLP control

## Quick Start

```powershell
# Deploy
./Deploy-Lab.ps1 -Cloud commercial -LabProfile copilot-dlp -TenantId <tenant-guid>

# Deploy without test users (use existing tenant accounts)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile copilot-dlp -TenantId <tenant-guid> -SkipTestUsers

# Dry run
./Deploy-Lab.ps1 -Cloud commercial -LabProfile copilot-dlp -WhatIf

# Teardown
./Remove-Lab.ps1 -Cloud commercial -LabProfile copilot-dlp -Confirm:$false -TenantId <tenant-guid>
```

## Lab Phases (90–120 minutes, modular)

| Phase | Title | Duration | Automated? |
|---|---|---|---|
| 0 | Baseline — Copilot without guardrails | 5 min | Manual (see RUNBOOK) |
| 1 | Block sensitive prompts (SIT-based) | 20 min | Automated (DLP policy) |
| 2 | Block labeled files from Copilot | 20 min | Automated (DLP policy) |
| 3 | Stop Copilot web search with sensitive data | 15 min | Manual/Preview (see RUNBOOK) |
| 4 | Evidence & investigations | 15 min | Automated (audit + eDiscovery) |

## Post-Deploy Manual Steps

The following items require manual configuration in the Purview compliance portal because the PowerShell cmdlets do not yet support them.

### 1. Create label-based DLP rules for Copilot

`New-DlpComplianceRule` has no parameter for sensitivity label conditions scoped to Copilot. The automated deployment creates the **Copilot Labeled Content Block** policy shell, but the two label-based rules must be added manually.

1. Open **Microsoft Purview** → **Data loss prevention** → **Policies**
2. Edit **PVCopilotDLP-Copilot Labeled Content Block**
3. Add rule **Block Copilot from Restricted Content**:
   - Condition: Content contains sensitivity label = `PVCopilotDLP-Highly-Confidential-Restricted`
   - Action: Block
   - User notification: _"Copilot cannot access this content. The file is labeled Highly Confidential — Restricted, which prevents Copilot from summarizing or referencing it."_
   - Alert severity: High
4. Add rule **Block Copilot from Regulated Data**:
   - Condition: Content contains sensitivity label = `PVCopilotDLP-Highly-Confidential-Regulated-Data`
   - Action: Block
   - User notification: _"Copilot cannot access this content. The file contains regulated data that is blocked from AI processing by policy."_
   - Alert severity: High
5. Save and publish the policy

### 2. Verify DLP enforcement settings on SIT rules

The three SIT-based rules (Block SSN / Credit Card / PHI in Copilot Prompts) may deploy with baseline settings only if the cmdlet does not support enforcement parameters for Copilot-scoped policies. Verify in the portal:

1. Open **PVCopilotDLP-Copilot Prompt SIT Block** policy
2. For each rule, confirm:
   - **Block access** is enabled
   - **User notifications** are enabled with the configured message
   - **Alert generation** is set to High severity
3. If any are missing, edit the rule and enable them manually

### 3. Scope DLP policies to Copilot location

If the `CopilotLocation` parameter is not yet available in your tenant's PowerShell module, the DLP policies may deploy without a Copilot location scope. Verify:

1. Open each DLP policy in the portal
2. Under **Locations**, confirm **Microsoft 365 Copilot & Copilot Chat** is selected
3. If missing, add the location and re-publish

## Key Technical Notes

- **SIT + label conditions cannot be mixed in the same DLP rule** for Copilot. This lab uses separate policies/rules for each condition type.
- DLP policies deploy in **simulation mode** (TestWithNotifications) by default. Switch to enforce for live demos.
- Phase 3 (web search prevention) requires **Private Preview** enrollment — documented in RUNBOOK.md.

## References

- [Learn about using Microsoft Purview DLP to protect interactions with Copilot](https://learn.microsoft.com/purview/dlp-microsoft-copilot)
- [Use Microsoft Purview to manage data security for M365 Copilot](https://learn.microsoft.com/purview/ai-microsoft-purview)
