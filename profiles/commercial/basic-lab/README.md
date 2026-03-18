# Basic Lab — Commercial Deployment Guide

Baseline Microsoft Purview lab demonstrating core compliance workloads.

## Quick start

```powershell
# Deploy
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic-lab -TenantId <tenant-guid>

# Deploy with new test user creation
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic-lab -TenantId <tenant-guid> -TestUsersMode create

# Dry run
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic-lab -WhatIf

# Remove
./Remove-Lab.ps1 -Cloud commercial -LabProfile basic-lab -Confirm:$false -TenantId <tenant-guid>
```

## Scope

- **Config:** `configs/commercial/basic-lab-demo.json`
- **Prefix:** `PVLab` (all resources scoped to this prefix)
- **Cloud:** commercial (also available as `configs/gcc/basic-lab-demo.json`)

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

- Offensive Language Monitoring policy

### Insider Risk Management

- Departing User Data Theft policy

### Test Data

- 6 sample emails with PII, financial data, and sensitive content
