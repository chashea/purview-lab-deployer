# Shadow AI Demo — GCC Deployment Guide

Comprehensive Shadow AI detection and governance demo for Microsoft Purview in GCC.

## Quick start

```powershell
# Deploy (uses existing Entra ID users by default)
./Deploy-Lab.ps1 -Cloud gcc -LabProfile shadow-ai -TenantId <tenant-guid>

# Deploy with new test user creation
./Deploy-Lab.ps1 -Cloud gcc -LabProfile shadow-ai -TenantId <tenant-guid> -TestUsersMode create

# Dry run
./Deploy-Lab.ps1 -Cloud gcc -LabProfile shadow-ai -WhatIf

# Remove
./Remove-Lab.ps1 -Cloud gcc -LabProfile shadow-ai -Confirm:$false -TenantId <tenant-guid>
```

## Scope

- **Config:** `configs/gcc/shadow-ai-demo.json`
- **Prefix:** `PVShadowAI` (all resources scoped to this prefix)
- **Cloud:** gcc
- **Lifecycle:** fully independent from baseline `basic-lab` deployment

## GCC-specific notes

- **Communication Compliance:** available but feature parity and release cadence may differ from commercial. Validate DSPM/advanced workflows in tenant.
- **Insider Risk Management:** available but rollout stage may differ. Validate in tenant before production runs.
- **MDCA portal URL:** GCC uses `.cloudappsecurity.us` (auto-detected by the deployer).
- **App Governance:** Cloud Discovery and session policy availability may vary by GCC tenant configuration.

## What gets deployed

### Identity (8 users, 3 groups)

| User | Department | Role |
|---|---|---|
| aharper | Marketing | Marketing Manager |
| vcho | Finance | Finance Controller |
| lramirez | Legal | Privacy Counsel |
| etran | IT Security | Security Analyst |
| kmills | HR | HR Specialist |
| pdesai | Compliance | Compliance Officer |
| opark | Engineering | Software Engineer |
| mahmed | Operations | Operations Lead |

**Groups:** AI-Governance, Privileged-Data-Owners, Business-Users

All users are auto-licensed with an Exchange-capable SKU for mailbox provisioning.

### Sensitivity Labels

- **Confidential** (parent) with sublabels: AI-Internal-Use, AI-Restricted-Recipients, AI-Blocked-from-External-Tools, AI-Regulated-Data
- **Highly Confidential** (parent) with sublabels: AI-Blocked-from-External-Tools, AI-Regulated-Data
- Auto-label policy for SSN detection
- Publication policy for all users

### DLP Policies (6 policies, 12 rules)

| Policy | Location | Mode | Rules |
|---|---|---|---|
| GenAI Prompt PII Protection | Devices | Visibility (audit) | SSN detection, Credit Card detection |
| GenAI Financial and Payroll Guardrail | Devices | Guardrail (warn) | Bank accounts + Customer IDs, SSN in payroll |
| External AI Upload Risk Signals | Copilot | High-risk block | Medical terms, Credit Cards |
| Labeled Data AI Restriction | Copilot | Label restriction | Restrict labeled data in AI |
| Endpoint AI Site Restrictions | Devices | High-risk block | Block sensitive upload to AI sites, Warn on paste |
| Adaptive AI Protection by Risk Level | Copilot | Adaptive | Elevated=block, Moderate=warn, Minor=audit |

**Blocked AI site URLs:** chat.openai.com, chatgpt.com, claude.ai, gemini.google.com, bard.google.com, copilot.microsoft.com, poe.com, perplexity.ai, huggingface.co/chat

All rules include policy tips with user education messages.

### Insider Risk Management (3 policies)

| Policy | Template | Priority Groups |
|---|---|---|
| Shadow AI Risky Usage Watch | Risky AI usage | All 3 groups |
| AI Data Exfiltration Watch | Data leaks | Business-Users |
| Departing User AI Risk | Data theft by departing users | AI-Governance, Privileged-Data-Owners |

### Communication Compliance (3 policies)

| Policy | Focus | Supervised Users |
|---|---|---|
| External AI Prompt Sharing Monitoring | Data sharing | aharper, opark, mahmed |
| Sensitive Business Data in AI Prompts | Business data disclosure | vcho, kmills, etran |
| Compliance Violations in AI Content | Compliance violations | aharper, opark, vcho, mahmed |

### Retention (2 policies)

- AI Prompt Review Retention — 1 year
- AI Incident Evidence Retention — 3 years

### eDiscovery

- Case: Shadow-AI-Incident-Review
- Custodians, hold, and search pre-configured

### Audit Configuration

- Unified audit logging enabled
- Searches validated: Copilot activity, DLP policy matches, external AI app access

### Conditional Access (2 policies, report-only)

| Policy | Action | Condition |
|---|---|---|
| Block AI Apps High Sign-In Risk | Block | High sign-in risk |
| Require MFA for AI App Access | MFA | All users |

Both policies deploy in report-only mode. Update `targetAppIds` in config with your tenant's enterprise app IDs for AI services.

### Test Data

**3 documents** uploaded to user OneDrive:
- Q4-Financial-Forecast.docx (Confidential) — financial data + customer IDs
- Customer-Data-Export.docx (Highly Confidential) — PII + API keys
- Engineering-Specs.docx (Confidential) — project codes + API keys

## Manual portal configuration required

The following items are documented in config but require manual setup:

### App Governance — OAuth App Policies (manual only)
OAuth app governance policy creation is not supported via API. See `appGovernance.manualSteps` in config:
- Navigate to **Microsoft Defender for Cloud Apps > App Governance > Policies**
- Create policy: condition = app requests `Mail.Read`, `Files.ReadWrite.All`, or `Sites.ReadWrite.All` AND app category contains "Generative AI"
- Action: Generate alert + optionally disable app

### App Governance — Automated via MDCA REST API
The following are deployed automatically by the `appGovernance` workload:
- **AI app tagging:** ChatGPT, Claude, Gemini, Perplexity, Poe, HuggingChat tagged as unsanctioned in MDCA catalog
- **Cloud Discovery policy:** Alert on Generative AI category usage exceeding 100 MB/day
- **Session policy:** Monitor uploads to AI apps with content inspection

Requires an MDCA API token (Entra app registration with Cloud App Security permissions) or `mdcaApiToken` in config.

### Endpoint DLP Browser Restrictions
The blocked AI site URL list is in config under `endpointDlpBrowserRestrictions`. To enforce:
1. Navigate to Purview portal > Data Loss Prevention > Endpoint DLP settings
2. Add browser restrictions for the listed AI domains
3. Configure unallowed browser list if needed

## Validation

- Deploy runs DLP preflight checks and post-deploy validation
- Unsupported cmdlet parameters degrade gracefully with warnings
- Enforcement validation is advisory (warnings, not failures)
