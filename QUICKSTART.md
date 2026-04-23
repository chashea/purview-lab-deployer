# Quick Start Guide

Get a Purview demo lab running in your tenant with DLP alerts, incidents, and Insider Risk signals in under 30 minutes.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **PowerShell 7+** | [Install pwsh](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| **M365 E5 or G5 license** | Required for DLP, Copilot DLP, Insider Risk, eDiscovery |
| **2+ licensed users** | With Exchange mailboxes and OneDrive provisioned |
| **Admin role** | Compliance Administrator + User Administrator |

### Install PowerShell modules

```powershell
Install-Module -Name ExchangeOnlineManagement -Force -Scope CurrentUser
Install-Module -Name Microsoft.Graph -Force -Scope CurrentUser
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```

---

## Step 1 — Clone the repo

```powershell
git clone https://github.com/chashea/purview-lab-deployer
cd purview-lab-deployer
```

---

## Step 2 — Create your config

Copy the template and edit it for your tenant:

```powershell
cp configs/commercial/basic-demo.json configs/commercial/my-lab.json
```

Open `configs/commercial/my-lab.json` and change these fields:

```json
{
  "labName": "My Purview Lab",
  "prefix": "PVLab",
  "domain": "YOUR-TENANT.onmicrosoft.com",
  "workloads": {
    "testUsers": {
      "enabled": true,
      "mode": "existing",
      "users": [
        { "upn": "user1@YOUR-TENANT.onmicrosoft.com" },
        { "upn": "user2@YOUR-TENANT.onmicrosoft.com" }
      ],
      "groups": [
        {
          "displayName": "PVLab-Executives",
          "members": ["user1", "user2"]
        }
      ]
    }
  }
}
```

**What to change:**
- `domain` → your tenant domain
- `testUsers.users` → UPNs of 2+ licensed users in your tenant
- `groups[].members` → mail nicknames (the part before @) of your users

**What to keep as-is:**
- `prefix` (PVLab) — all resources are tagged with this for easy cleanup
- `mode: "existing"` — uses your existing users, won't create new ones
- All DLP policy/rule definitions, label structures, retention policies

---

## Step 3 — Deploy the lab

```powershell
# Dry run first (no cloud connection)
./Deploy-Lab.ps1 -ConfigPath configs/commercial/my-lab.json -SkipAuth -WhatIf

# Deploy for real (opens browser for auth)
./Deploy-Lab.ps1 -ConfigPath configs/commercial/my-lab.json -Cloud commercial
```

This creates:
- DLP policies with SIT-based rules (SSN, credit card, bank account, medical)
- Sensitivity labels (Confidential + Highly Confidential trees)
- Retention policies
- eDiscovery cases
- Communication compliance policies
- Insider Risk policies

---

## Step 4 — Run smoke tests

### Option A: Standalone mode (no config file needed)

```powershell
./scripts/Invoke-SmokeTest.ps1 `
    -TenantId "YOUR-TENANT-ID" `
    -Domain "YOUR-TENANT.onmicrosoft.com" `
    -Users "user1@YOUR-TENANT.onmicrosoft.com","user2@YOUR-TENANT.onmicrosoft.com"
```

### Option B: Config mode (uses your lab config)

```powershell
./scripts/Invoke-SmokeTest.ps1 -ConfigPath configs/commercial/my-lab.json -Cloud commercial
```

### DLP + Insider Risk burst activity

Add `-BurstActivity` to either mode for high-volume IRM signals:

```powershell
# Standalone with burst
./scripts/Invoke-SmokeTest.ps1 `
    -TenantId "YOUR-TENANT-ID" `
    -Domain "YOUR-TENANT.onmicrosoft.com" `
    -Users "user1@YOUR-TENANT.onmicrosoft.com","user2@YOUR-TENANT.onmicrosoft.com" `
    -BurstActivity

# Config with burst
./scripts/Invoke-SmokeTest.ps1 -ConfigPath configs/commercial/my-lab.json -BurstActivity
```

### Copilot DLP testing

Open [M365 Copilot Chat](https://m365.cloud.microsoft/chat) and paste prompts from `scripts/copilot-test-prompts.md`. Each prompt contains sensitive data that triggers Copilot DLP classifiers.

---

## Step 5 — Validate

```powershell
# Check audit log for DLP matches
./scripts/Invoke-SmokeTest.ps1 -ConfigPath configs/commercial/my-lab.json -ValidateOnly -Since (Get-Date).AddHours(-1)
```

Or check the portals directly:

| What | Portal URL |
|---|---|
| DLP Alerts | https://purview.microsoft.com/datalossprevention/alerts |
| Activity Explorer | https://purview.microsoft.com/datalossprevention/activityexplorer |
| Insider Risk | https://purview.microsoft.com/insiderriskmanagement/alerts |
| Audit Log | https://purview.microsoft.com/audit |

---

## Teardown

When you're done, remove all lab resources:

```powershell
./Remove-Lab.ps1 -ConfigPath configs/commercial/my-lab.json -Cloud commercial
```

All resources are prefixed with `PVLab-` for reliable cleanup.

---

## Troubleshooting

| Issue | Fix |
|---|---|
| `Connect-ExchangeOnline` fails | Run `Install-Module ExchangeOnlineManagement -Force` |
| DLP rules not creating | Ensure you have Compliance Administrator role |
| No DLP alerts after smoke test | Wait 15-60 minutes; check rules have alerting enabled |
| OneDrive uploads fail | Ensure users have OneDrive provisioned (visit onedrive.com as each user once) |
| Insider Risk no alerts | IRM needs 24-48 hours; ensure IRM policies are enabled in Purview |
| TestUsers "department" error | Transient Graph issue — safe to ignore, other workloads still deploy |

---

## Available profiles

| Profile | Command | What it deploys |
|---|---|---|
| **basic** | `-LabProfile basic` | Core compliance: OneDrive/Teams/Outlook/SharePoint DLP, labels, retention, eDiscovery, insider risk, audit config. Prefix `PVLab`. |
| **ai** | `-LabProfile ai` | Copilot + gen-AI governance: Copilot DLP, Shadow AI (Endpoint/Browser/Network), AI labels, IRM, Sentinel. Prefix `PVAI`. Requires an Azure subscription. |
| **purview-sentinel** | `-LabProfile purview-sentinel` | Sentinel workspace + Defender XDR / IRM / Office 365 connectors + Purview-focused analytics rules and workbook. Requires an Azure subscription and `az login`; fill in `subscriptionId` in the demo config first. |

Each profile uses its own config under `configs/commercial/`. Copy and customize for your tenant.
