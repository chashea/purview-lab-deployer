# Shadow AI Prevention Demo — Commercial Deployment Guide

Comprehensive Shadow AI detection and governance demo for Microsoft Purview. Covers the full chain: discover external AI usage, block sensitive data from leaving to public AI sites, steer users to sanctioned Copilot, and correlate risky behavior via Insider Risk.

## Prerequisites

1. **Microsoft 365 E5** (or E5 Compliance add-on) for full Purview stack
2. **Microsoft 365 Copilot** licenses for demo users (so the "use Copilot instead" story is demonstrable)
3. **Microsoft Defender for Endpoint** on test devices (required for Endpoint DLP browser restrictions to enforce on paste/upload activities)
4. **PowerShell 7+** (`pwsh --version` returns 7.x)
5. **Git** to clone the repo

## Getting the repository

```bash
git clone https://github.com/chashea/purview-lab-deployer.git
cd purview-lab-deployer
```

## Deploy the Shadow AI lab

From inside the repo, run **one command**:

```powershell
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -TenantId <tenant-guid>
```

### Optional variations

```powershell
# Deploy without creating test users (use your own accounts)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -TenantId <tenant-guid> -SkipTestUsers

# Dry run — preview what would be created without making changes
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -WhatIf

# Teardown
./Remove-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -Confirm:$false -TenantId <tenant-guid>
```

### Post-deploy readiness check

```powershell
./scripts/Test-ShadowAiReady.ps1 -LabProfile shadow-ai -Cloud commercial
```

Exit codes: `0` = ready, `1` = wait (propagating / missing domains / license gaps), `2` = blocked (missing policy, label, or IRM).

## Scope

- **Config:** `configs/commercial/shadow-ai-demo.json`
- **Prefix:** `PVShadowAI` (all resources scoped to this prefix)
- **Cloud:** commercial
- **Lifecycle:** fully independent from baseline `basic-lab` and `copilot-protection` deployments

## What gets deployed

### Test users (5 users, 3 groups)

| UPN alias | Role persona |
|---|---|
| rtorres | Marketing / business user |
| mchen | Finance / privileged data owner |
| nbrooks | IT Security / governance |
| dokafor | Compliance lead |
| sreeves | AI governance lead |

**Groups:** `PVShadowAI-AI-Governance`, `PVShadowAI-Privileged-Data-Owners`, `PVShadowAI-Business-Users`

Caller-supplied accounts can replace these via `-TestUsers alice@contoso.com,bob@contoso.com`.

### Sensitivity labels

| Parent | Sublabels |
|---|---|
| Confidential | All Employees, AI Internal Use, AI Restricted Recipients, AI Blocked from External Tools, AI Regulated Data |
| Highly Confidential | All Employees, AI Internal Use, AI Restricted Recipients, AI Blocked from External Tools, AI Regulated Data |

Auto-label policies:
- SSN content → `Highly Confidential > AI Regulated Data`
- Credit Card / Bank Account / IBAN / IP Address → `Confidential > AI Regulated Data`

Plus a publication policy for all users.

### DLP policies (5 policies, 13 rules)

| Policy | Location | Purpose | Risk-tiered rules |
|---|---|---|---|
| Shadow AI - Endpoint Protection | Devices | Paste/upload to unmanaged AI sites on managed devices | Elevated = block, Moderate = warn, Minor = audit |
| Shadow AI - Browser Prompt Protection | Browser (ThirdPartyApp) | Inline detection of sensitive text typed into browser-based AI apps | Elevated = block, Moderate = warn, Minor = audit |
| Shadow AI - Network AI Traffic | Network (SASE/SSE) | Detect sensitive outbound traffic to AI apps via non-Microsoft browsers | Elevated = block, Moderate = warn, Minor = audit |
| Shadow AI - Copilot Prompt Protection | CopilotExperiences | Microsoft 365 Copilot prompt SIT blocking | Elevated = block, Moderate = warn, Minor = audit |
| Shadow AI - Copilot Label Protection | CopilotExperiences | Block Copilot from labeled content | Block labeled content |

**Endpoint DLP browser block list** (applied via `scripts/Set-ShadowAiEndpointDlpDomains.ps1`):
`chat.openai.com, chatgpt.com, claude.ai, gemini.google.com, bard.google.com, copilot.microsoft.com, poe.com, perplexity.ai, huggingface.co/chat`

All rules default to **simulation mode** (`TestWithNotifications`). Flip `"simulationMode": false` in config and redeploy for live enforcement — then budget 4h propagation.

### Insider Risk Management (6 policies)

| Policy | Template | Focus |
|---|---|---|
| Shadow AI Risky Usage Watch | Risky AI usage | General AI behavioral signals |
| AI Data Exfiltration Watch | Data leaks | Sensitive data flowing to AI destinations |
| Departing User AI Risk | Data theft by departing users | Resignation + AI access correlation |
| DSPM for AI - Detect risky AI usage | Risky AI usage | Prompt injection, protected material access |
| DSPM for AI - Business User AI Risk | Risky AI usage | Scoped to Business Users group |
| DLP Correlated AI Exfiltration | Data leaks | Consumes DLP alerts as risk signals |

### Communication Compliance (2 policies)

- **Shadow AI Activity Collection** — review queue for AI-related messages
- **AI Conversation PII PHI Detection** — targeted PII/PHI detection in AI-adjacent conversations

### Retention (5 policies)

- AI Prompt Review Retention (365 days, Exchange + SharePoint)
- AI Incident Evidence Retention (3 years, Exchange + OneDrive)
- Copilot Experiences Retention (365 days, `-Applications MicrosoftCopilotExperiences`)
- Enterprise AI Apps Retention (3 years, `-Applications EnterpriseAIApps`)
- Other AI Apps Retention (365 days, `-Applications OtherAIApps`)

### eDiscovery

- Case: `Shadow-AI-Incident-Review` with custodians, hold queries, and search queries pre-configured

### Audit searches (3 saved searches)

- Copilot Activity Audit — `CopilotInteraction` + `MicrosoftCopilotForM365`
- DLP Policy Match Audit — `DlpRuleMatch`
- External AI App Access Audit — `FileUploaded`, browser events

### Conditional Access (report-only)

Two policies target AI cloud apps:
- Block AI apps for high sign-in risk
- Require MFA for AI app access

Both deploy in report-only mode. Replace `targetAppIds` with your tenant's enterprise app IDs for ChatGPT / Claude / Gemini to enforce.

### Test data

5 documents uploaded to user OneDrive, auto-labeled at deploy via Graph `assignSensitivityLabel`:

| File | Owner | Label |
|---|---|---|
| Q4-Financial-Forecast.docx | mchen | Confidential > All Employees |
| Customer-Data-Export.docx | rtorres | Highly Confidential > AI Regulated Data |
| Engineering-Specs.docx | dokafor | Confidential > AI Internal Use |
| HR-Compensation-Analysis.docx | mchen | Highly Confidential > AI Blocked from External Tools |
| AI-Usage-Policy-Draft.docx | sreeves | Confidential > All Employees |

## Post-deploy steps

1. **Run the readiness check** — `./scripts/Test-ShadowAiReady.ps1 -LabProfile shadow-ai`.
2. **Push Endpoint DLP browser restrictions** — `./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile shadow-ai` to preview, then `-Apply`. Tenant-wide setting; review current values before applying.
3. **Optional: Activate DSPM for AI one-click policies** — see `RUNBOOK.md` for the full list of recommended activations.
4. **Onboard test devices to Defender for Endpoint** — required for Endpoint DLP enforcement on paste/upload.

## References

- [MS Learn: Shadow AI data leak deployment guide](https://learn.microsoft.com/purview/deploymentmodels/depmod-data-leak-shadow-ai-step3)
- [MS Learn: DSPM for AI one-click policies](https://learn.microsoft.com/purview/dspm-for-ai-considerations#one-click-policies-from-data-security-posture-management-for-ai)
- [MS Learn: Browser Data Security for Edge](https://learn.microsoft.com/purview/dlp-browser-dlp-learn)
- [MS Learn: Network Data Security](https://learn.microsoft.com/purview/dlp-network-data-security-learn)
- [MS Learn: Retention for Copilot & AI apps](https://learn.microsoft.com/purview/retention-policies-copilot)

## Validation

- Deploy runs DLP preflight checks and Copilot license preflight
- Unsupported cmdlet parameters degrade gracefully with warnings
- `Test-ShadowAiReady.ps1` catches missing policies, labels, licenses, and endpoint DLP domain gaps before demo day
- Pester tests verify config shape (run `Invoke-Pester tests/`)
