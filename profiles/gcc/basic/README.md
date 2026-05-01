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

- **Confidential** (parent) with sublabels: Internal, Recipients-Only, Anyone-No-Forwarding, Financial-Data, Legal-Privileged
- **Highly Confidential** (parent) with sublabels: Internal, Recipients-Only, Anyone-No-Forwarding, Board-Only, Regulated-Data
- Auto-label policies for SSN and credit card detection

### DLP Policies

| Policy | Location | Rules |
|---|---|---|
| US PII Protection | Exchange, SharePoint, OneDrive, Teams | SSN detection (min 5) |
| Financial Data Protection | Exchange, SharePoint, OneDrive | Credit card detection (min 1) |
| HR Case Data Protection | Exchange, SharePoint | SSN detection (min 1) |
| Workplace Health Record Protection | Exchange, SharePoint | SSN + medical terms (min 1) |

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

- 6 sample emails with PII, financial data, and sensitive content
