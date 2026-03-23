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

## Key Technical Notes

- **SIT + label conditions cannot be mixed in the same DLP rule** for Copilot. This lab uses separate policies/rules for each condition type.
- DLP policies deploy in **simulation mode** (TestWithNotifications) by default. Switch to enforce for live demos.
- Phase 3 (web search prevention) requires **Private Preview** enrollment — documented in RUNBOOK.md.

## References

- [Learn about using Microsoft Purview DLP to protect interactions with Copilot](https://learn.microsoft.com/purview/dlp-microsoft-copilot)
- [Use Microsoft Purview to manage data security for M365 Copilot](https://learn.microsoft.com/purview/ai-microsoft-purview)
