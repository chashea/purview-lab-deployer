# Basic Lab — GCC Deployment Guide

Baseline Microsoft Purview lab demonstrating core compliance workloads in GCC.

## Quick start

```powershell
# Deploy
./Deploy-Lab.ps1 -Cloud gcc -LabProfile basic -TenantId <tenant-guid>

# Deploy with new test user creation
./Deploy-Lab.ps1 -Cloud gcc -LabProfile basic -TenantId <tenant-guid> -TestUsersMode create

# Dry run
./Deploy-Lab.ps1 -Cloud gcc -LabProfile basic -WhatIf

# Remove
./Remove-Lab.ps1 -Cloud gcc -LabProfile basic -Confirm:$false -TenantId <tenant-guid>
```

## Scope

- **Config:** `configs/gcc/basic-demo.json`
- **Prefix:** `PVLab` (all resources scoped to this prefix)
- **Cloud:** gcc

## GCC-specific notes

- **Communication Compliance:** available but feature parity and release cadence may differ from commercial. Validate DSPM/advanced workflows in tenant.
- **Insider Risk Management:** available but rollout stage may differ. Validate in tenant before production runs.

## What gets deployed

### Identity (8 users, 3 groups)

The basic GCC lab targets **pre-existing demo tenant accounts** in `MngEnvMCAP659995.onmicrosoft.com` (no users are created by the deployer):

| User UPN | Group memberships |
|---|---|
| mtorres@... | Legal-Team |
| mahmed@... | Finance-Team |
| nshah@... | Legal-Team |
| opark@... | — |
| DebraB@... | Executives |
| NestorW@... | Executives, Finance-Team |
| JoniS@... | — |
| jkim@... | Legal-Team |

**Groups:** `PVLab-Executives`, `PVLab-Finance-Team`, `PVLab-Legal-Team`

### Sensitivity Labels

- **Confidential** (parent) with sublabels: `Medical`, `Financial`, `HR`, `All-Employees`, `Recipients Only`
- **Highly Confidential** (parent) with sublabels: `Medical`, `Financial`, `HR`, `All-Employees`, `Recipients Only`
- Auto-label policies for SSN and credit card detection
- Sublabel identities follow the pattern `PVLab-<parent>-<sublabel>` with spaces replaced by hyphens (e.g. `PVLab-Highly-Confidential-Financial`)

### DLP Policies

| Policy | Locations | Rules (SIT, minCount, action) |
|---|---|---|
| US PII Protection | Exchange, SharePoint, OneDrive | SSN (min 1, block); Credit Card (min 1, block) |
| Financial Data Protection | Exchange, SharePoint, OneDrive, Teams | U.S. Bank Account Number (min 1, block); Credit Card (min 1, block) |
| HR Case Data Protection | Exchange, SharePoint, OneDrive | SSN (min 1, block); U.S. Bank Account Number (min 1, block) |
| Workplace Health Record Protection | Exchange, SharePoint, OneDrive, Teams | All Medical Terms And Conditions (min 1, block); SSN (min 1, block) |

> All four policies are exercised by `scripts/Invoke-SmokeTest.ps1` via Exchange (sendMail) and OneDrive (file upload). Teams chat traffic is not exercised by the smoke test — Teams DLP signals must be validated manually.

### Retention Policies

- Financial Records Retention — 2555 days (7 years)
- Legal Hold — 365 days

### eDiscovery

- Case: Data-Breach-Investigation with custodians, hold, and search

### Communication Compliance

- Inappropriate Text Policy

> Implemented as a DSPM for AI Know Your Data collection policy
> (`New-FeatureConfiguration -FeatureScenario KnowYourData`), not a classic
> Communication Compliance template — the `SupervisoryReviewPolicyV2`
> cmdlets are retired. Captures Copilot `UploadText`/`DownloadText`
> activity across all sensitive info types. Full review/remediation flow
> is configured in the Microsoft Purview portal under
> **DSPM for AI → Recommendations → Control Unethical Behavior in AI**.

### Insider Risk Management

- Departing User Data Theft policy

### Test Data

**Emails (10):** Sent via Graph from the signed-in admin to the user pairs below. Each carries content designed to fire one or more DLP rules (SSN, Credit Card, Bank Account, Medical Terms) or match the eDiscovery case content query.

| From | To | Trigger |
|---|---|---|
| mahmed → NestorW | Q4 Financial Summary | Bank Account |
| DebraB → mahmed | Client Payment Issue | Credit Card |
| mtorres → nshah | Background Check Results | SSN |
| opark → NestorW | Insider Trading Concern | eDiscovery / IRM signal |
| jkim → mtorres | HR Investigation Packet | SSN |
| JoniS → jkim | Workplace Accommodation | Medical |
| mahmed → DebraB | Vendor ACH Wire PMT-228 | Bank Account |
| jkim → nshah | Workplace Conduct Allegation | eDiscovery (harassment / hostile / inappropriate behavior) |
| jkim → mtorres | Patient Referral Cardiology | Medical |
| mtorres → jkim | Termination Paperwork SSN | SSN + Bank Account |

**Documents (6):** Uploaded to the owner's OneDrive root via Graph, then optionally tagged with a sensitivity label via `assignSensitivityLabel`. Exercises file-surface DLP, label adoption, auto-label policies, and IRM file-activity signals.

| File | Owner | Label | Trigger |
|---|---|---|---|
| `Q4-Board-Financials.docx` | NestorW | `PVLab-Highly-Confidential-Financial` | Financial Data Protection (Bank Account) |
| `Customer-Master-List.docx` | DebraB | `PVLab-Highly-Confidential-All-Employees` | US PII Protection (SSN + Credit Card) |
| `Patient-Health-Records.docx` | jkim | `PVLab-Confidential-Medical` | Workplace Health Record Protection (Medical + SSN) |
| `HR-Termination-Packet.docx` | mtorres | `PVLab-Confidential-HR` | HR Case Data Protection (SSN + Bank Account) |
| `Legal-Discovery-Notes.docx` | nshah | `PVLab-Highly-Confidential-Recipients-Only` | eDiscovery case content query |
| `Departing-Employee-Files.docx` | opark | *(none)* | Auto-label policies + IRM departing-user file-activity |

> Test emails cannot be recalled. Documents persist in OneDrive until manually deleted (TestData removal is intentionally a no-op).
