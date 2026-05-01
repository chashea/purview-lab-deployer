# Basic Lab — Commercial Deployment Guide

Baseline Microsoft Purview lab demonstrating core compliance workloads.

## Quick start

```powershell
git clone https://github.com/chashea/purview-lab-deployer.git
cd purview-lab-deployer

# Deploy (test users auto-created)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic -TenantId <tenant-guid>

# Deploy without test users
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic -TenantId <tenant-guid> -SkipTestUsers

# Dry run
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic -WhatIf

# Remove
./Remove-Lab.ps1 -Cloud commercial -LabProfile basic -Confirm:$false -TenantId <tenant-guid>
```

## Scope

- **Config:** `configs/commercial/basic-demo.json`
- **Prefix:** `PVLab` (all resources scoped to this prefix)
- **Cloud:** commercial (also available as `configs/gcc/basic-demo.json`)

## What gets deployed

### Identity (8 users, 3 groups)

| User | Department | Role |
|---|---|---|
| rtorres | Executive | Chief Compliance Officer |
| mchen | Finance | Finance Analyst |
| nbrooks | Legal | General Counsel |
| dokafor | IT | IT Manager |
| sreeves | HR | HR Director |
| jblake | Sales | Sales Director |
| msullivan | Marketing | Marketing VP |
| pnair | Engineering | Engineering Lead |

**Groups:** Executives, Finance-Team, Legal-Team

### Sensitivity Labels

- **Confidential** (parent) with sublabels: Internal, Recipients-Only, Anyone-No-Forwarding, Regulated-Data, Vertical-Specific
- **Highly Confidential** (parent) with sublabels: Internal, Recipients-Only, Anyone-No-Forwarding, Regulated-Data, Vertical-Specific
- Auto-label policies:
  - SSN → `Highly Confidential\Regulated-Data`
  - Credit Card → `Highly Confidential\Regulated-Data`
  - EIN / IBAN / SWIFT → `Confidential\Internal`

### DLP Policies

| Policy | Locations | Scope | Rules |
|---|---|---|---|
| US PII Protection | Exchange, SharePoint, OneDrive, Teams | All users | SSN ≥5, Credit Card ≥5 |
| Financial Data Protection | Exchange, SharePoint, OneDrive, Teams | `PVLab-Finance-Team` | Bank account ≥1, Credit card ≥1 |
| HR Case Data Protection | Exchange, SharePoint, OneDrive, Teams | `PVLab-Legal-Team` | SSN ≥1, Bank account ≥1 |
| Workplace Health Record Protection | Exchange, SharePoint, Teams | All users | Medical terms ≥1, SSN ≥1 |
| Confidential Label Egress Block | Exchange, SharePoint, OneDrive, Teams | All users | Block content labeled `Highly Confidential\Regulated-Data` |

### Retention Policies

- Financial Records Retention — 2555 days (7 years)
- Legal Hold — 365 days

### eDiscovery

- Case: `Data-Breach-Investigation` — custodians, hold, searches, review sets
- Case: `HR-Investigation` — custodians, hold, searches, review sets

### Communication Compliance

- DSPM-for-AI collection policy: `Workplace AI Activity Monitoring` (captures Copilot/enterprise-AI prompt + response activity for review)

### Insider Risk Management

- `Departing User Data Theft` (priority: Executives)
- `General-Data-Leaks` (all users)
- `Priority-Executive-Data-Exfil` (priority: Executives)
- `Security-Policy-Violations` (all users)

### Conditional Access (report-only)

- `Require-MFA-AllUsers`
- `Block-HighRisk-SignIns`
- `Require-Compliant-Device`

### Audit

- 7 saved audit searches: DLP match/override, file access, sharing, mailbox permissions, admin role changes, sign-in failures

### Test Data

- 7 sample emails covering single-instance PII (SSN/CC/bank), bulk SSN dump (triggers US PII threshold), workplace health records, insider-trading concern, and HR investigation packet
