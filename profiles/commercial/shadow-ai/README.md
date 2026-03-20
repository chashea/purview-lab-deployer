# Shadow AI Demo — Commercial Deployment Guide

Comprehensive Shadow AI detection and governance demo for Microsoft Purview.

## Prerequisites

Before you begin, make sure you have the following installed on your machine:

1. **Git** — used to download the repository.
   - **Windows:** Download and install from [git-scm.com](https://git-scm.com/download/win). Use the default options during install.
   - **macOS:** Open Terminal and run `xcode-select --install`, or install from [git-scm.com](https://git-scm.com/download/mac).
   - **Linux:** Run `sudo apt install git` (Debian/Ubuntu) or `sudo dnf install git` (Fedora).
   - To verify Git is installed, open a terminal and run: `git --version`

2. **PowerShell 7+** — the scripts require PowerShell 7 or later (not Windows PowerShell 5.1).
   - Install from [learn.microsoft.com/powershell/scripting/install](https://learn.microsoft.com/powershell/scripting/install/installing-powershell).
   - To verify, run: `pwsh --version`

## Getting the repository

Open a terminal (Terminal on macOS/Linux, PowerShell or Command Prompt on Windows) and run:

```bash
git clone https://github.com/chashea/purview-lab-deployer.git
```

This creates a `purview-lab-deployer` folder in your current directory. Next, navigate into it:

```bash
cd purview-lab-deployer
```

> **Tip:** If you're not sure where the folder was created, run `pwd` (macOS/Linux) or `cd` (Windows) to see your current directory path.

## Deploy the Shadow AI lab

From inside the `purview-lab-deployer` folder, open a **PowerShell 7** session (run `pwsh` if you're in a different shell) and run **one command**:

```powershell
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -TenantId <tenant-guid>
```

Replace `<tenant-guid>` with your Microsoft 365 tenant ID. That's it — this single command deploys the full Shadow AI demo environment, including test users, policies, labels, and test data.

### Optional variations

```powershell
# Deploy without creating test users (use your own accounts)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -TenantId <tenant-guid> -SkipTestUsers

# Dry run — preview what would be created without making changes
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -WhatIf

# Remove everything when you're done
./Remove-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -Confirm:$false -TenantId <tenant-guid>
```

## Scope

- **Config:** `configs/commercial/shadow-ai-demo.json`
- **Prefix:** `PVShadowAI` (all resources scoped to this prefix)
- **Cloud:** commercial
- **Lifecycle:** fully independent from baseline `basic-lab` deployment

## What gets deployed

### Identity (5 users, 3 groups)

| User | Department | Role |
|---|---|---|
| aharper | Marketing | Marketing Manager |
| vcho | Finance | Finance Controller |
| lramirez | Legal | Privacy Counsel |
| etran | IT Security | Security Architect |
| pdesai | Compliance | Compliance Lead |

**Groups:** AI-Governance, Privileged-Data-Owners, Business-Users

All users are auto-created and licensed by default. Use `-SkipTestUsers` to skip user creation.

### Sensitivity Labels

- **Confidential** (parent) with sublabels: AI-Internal-Use, AI-Restricted-Recipients, AI-Blocked-from-External-Tools, AI-Regulated-Data
- **Highly Confidential** (parent) with sublabels: AI-Blocked-from-External-Tools, AI-Regulated-Data
- Auto-label policy: SSN → Highly Confidential\AI Regulated Data
- Auto-label policy: Credit Card, Bank Account, IBAN, IP Address → Confidential\AI Regulated Data
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

Both policies deploy in report-only mode. Update `targetAppIds` in config with your tenant's enterprise app IDs for AI services (ChatGPT, Claude, etc.).

### Test Data

**3 documents** uploaded to user OneDrive:
- Q4-Financial-Forecast.docx (Confidential) — financial data + customer IDs
- Customer-Data-Export.docx (Highly Confidential) — PII + API keys
- Engineering-Specs.docx (Confidential) — project codes + API keys

## Manual portal configuration required

The following items are documented in config but require manual setup:

### Endpoint DLP Browser Restrictions
The blocked AI site URL list is in config under `endpointDlpBrowserRestrictions`. To enforce:
1. Navigate to Purview portal > Data Loss Prevention > Endpoint DLP settings
2. Add browser restrictions for the listed AI domains
3. Configure unallowed browser list if needed

## Demo scenarios

### Scenario 1: Shadow AI Discovery
1. Show unified audit log entries for external AI app access
2. Display DLP policy matches for AI site uploads in Activity Explorer
3. Show volume of data being shared via audit searches

### Scenario 2: Data Protection
1. Attempt to paste sensitive content into ChatGPT → blocked by DLP
2. Show policy tip educating user to use Copilot instead
3. Display audit trail of the attempted violation in Activity Explorer

### Scenario 3: Risky User Detection
1. Show Insider Risk policies detecting AI exfiltration patterns
2. Demonstrate risk score escalation (Minor → Moderate → Elevated)
3. Show Adaptive Protection tightening DLP enforcement automatically
4. Walk through investigation workflow in Insider Risk Management

### Scenario 4: Sanctioned vs. Unsanctioned AI
1. Copilot usage = allowed and monitored (Communication Compliance)
2. External AI tools = blocked or heavily restricted (DLP + Endpoint)
3. Show governance parity: same data, different enforcement by tool

### Presentation flow
1. **Problem statement** — risk landscape and shadow AI adoption stats
2. **Discovery** — "Here's what we found in YOUR environment"
3. **Governance** — "Here's how we protect you"
4. **User experience** — "Here's how users are guided to safe alternatives"
5. **Reporting** — "Here's how you maintain compliance and visibility"

## Validation

- Deploy runs DLP preflight checks and post-deploy validation
- Unsupported cmdlet parameters degrade gracefully with warnings
- Enforcement validation is advisory (warnings, not failures)
