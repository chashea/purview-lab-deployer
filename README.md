![Validate PowerShell](https://github.com/chashea/purview-lab-deployer/actions/workflows/validate.yml/badge.svg)
![GitHub release](https://img.shields.io/github/v/release/chashea/purview-lab-deployer)

# purview-lab-deployer

Config-driven Microsoft Purview demo lab deployment. PowerShell 7+, modular by workload, deploy and teardown symmetry.

## Deployment profiles

| Profile | Description | Guide |
|---------|-------------|-------|
| **basic-lab** | Core compliance workloads (DLP, labels, retention, eDiscovery, insider risk) | [profiles/commercial/basic-lab/README.md](profiles/commercial/basic-lab/README.md) |
| **shadow-ai** | Shadow AI detection and governance (AI app blocking, discovery, session monitoring) | [profiles/commercial/shadow-ai/README.md](profiles/commercial/shadow-ai/README.md) |
| **copilot-protection** | Copilot DLP guardrails for Copilot + Copilot Chat (prompt blocking, labeled content protection, web-search boundaries, audit evidence) | [profiles/commercial/copilot-dlp/README.md](profiles/commercial/copilot-dlp/README.md) |
| **purview-sentinel** | Send Purview DLP / Insider Risk / sensitivity-label signals into a Microsoft Sentinel workspace (Log Analytics + data connectors + analytics rules + workbook). Requires an Azure subscription. | [configs/commercial/purview-sentinel-demo.json](configs/commercial/purview-sentinel-demo.json) |

Each profile is a self-contained deployment with its own prefix, config, and lifecycle. See the profile README for setup instructions.

By default each profile uses the test users listed in its config. Pass `-TestUsers <upn>[,<upn>...]` to Deploy-Lab.ps1 to run the same profile against your own pre-licensed tenant users instead.

## How it works

1. Pick a profile (or point to a config JSON directly)
2. The orchestrator imports workload modules, checks cloud capabilities, and deploys in dependency order
3. A manifest is exported for precise teardown later
4. Teardown reverses the deployment using the manifest or falls back to prefix-based cleanup

## Workload modules

| Module | Automation | What it does |
|--------|------------|--------------|
| TestUsers | Full | Entra ID users and groups |
| SensitivityLabels | Full | Labels and auto-label policies |
| DLP | Full | Policies and rules with enforcement config |
| Retention | Full | Retention policies |
| EDiscovery | Full | Cases, custodians, holds, searches |
| CommunicationCompliance | Full | Supervision policies |
| InsiderRisk | Full | Insider risk management policies |
| ConditionalAccess | Full | CA policies (report-only mode) |
| AuditConfig | Full | Audit log searches |
| TestData | Full | Test emails and documents with sensitive content |

## Prerequisites

- PowerShell 7+ (`pwsh`)
- Microsoft 365 E5 (or E5 Compliance add-on)
- Roles: Compliance Administrator, User Administrator, eDiscovery Administrator

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
```

### Additional prerequisites for `purview-sentinel`

The `purview-sentinel` profile is the only profile that provisions Azure
subscription resources (resource group, Log Analytics workspace, Sentinel).

- Azure subscription + **Owner** or (**Contributor** + **User Access
  Administrator**) on the target subscription
- Azure CLI 2.50+ on PATH (`az --version`)
- `az login` into the tenant that owns the subscription and
  `az account set --subscription <id>` before running
- Providers registered: `Microsoft.OperationalInsights`, `Microsoft.SecurityInsights`
  (run `az provider register --namespace <ns>` if needed)
- Update `configs/commercial/purview-sentinel-demo.json` and fill in the
  `workloads.sentinelIntegration.subscriptionId` GUID

**Content Hub solutions (required for 2 of 3 connectors).** Microsoft Sentinel
now routes the Defender XDR and Purview Insider Risk Management data connectors
through *Content Hub solution installs*, not direct ARM `PUT /dataConnectors`
calls. Before you can finish wiring up those two connectors, install these
solutions in the Sentinel portal:

1. Open the Sentinel workspace → **Content hub**
2. Search for **Microsoft Defender XDR** → *Install*
3. Search for **Microsoft Purview Insider Risk Management** → *Install*
4. Re-run `Deploy-Lab.ps1` (it is idempotent) *or* manually enable both data
   connectors from the **Data connectors** blade

The deployment script detects this situation and emits a clear remediation
warning for each affected connector — the Office 365 connector, analytics
rules and workbook deploy without any Content Hub prerequisite.

Tenant-side caveat (not ARM-configurable): to receive **Insider Risk
Management** alerts in Sentinel, enable *SIEM export* in the Microsoft Purview
portal under **Insider risk management → Settings → Export alerts**. The
deployment will emit a warning reminder after provisioning.

The Microsoft Purview (Azure) data-sensitivity product is a separate service
and is out of scope for this lab — the `purview-sentinel` profile targets
Microsoft Purview (M365) compliance signals only.

## Quick start

```powershell
git clone https://github.com/chashea/purview-lab-deployer.git
cd purview-lab-deployer

# Interactive (prompts for cloud, profile, tenant)
./Deploy-Lab-Interactive.ps1

# Or specify directly
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -TenantId <tenant-guid>

# Bring your own pre-licensed tenant users (overrides the users in the config)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic-lab -TestUsers alice@contoso.com,bob@contoso.com

# Sentinel integration lab (requires an Azure subscription — see prerequisites above)
az login
az account set --subscription <subscription-id>
./Deploy-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel

# Tear down Sentinel lab (non-destructive by default; child resources only)
./Remove-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel -ManifestPath ./manifests/commercial/<name>.json

# Tear down AND delete the Sentinel resource group (only if the module created it and tags match)
./Remove-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel -ManifestPath ./manifests/commercial/<name>.json -ForceDeleteResourceGroup
```

## Supported clouds

| Cloud | Configs | Notes |
|-------|---------|-------|
| **commercial** | `configs/commercial/` | Full feature support |
| **gcc** | `configs/gcc/` | Some workloads limited — see `profiles/gcc/capabilities.json` |

## Smoke tests

Scripts in `scripts/` generate DLP alerts and Copilot activity for validating deployed policies.

| Script | What it does |
|--------|-------------|
| `Invoke-SmokeTest.ps1` | Send emails + upload OneDrive files with fake sensitive data (SSN, CC, bank, medical) to trigger Exchange/SharePoint/OneDrive DLP |
| `copilot-test-prompts.md` | 13 ready-to-paste prompts for M365 Copilot Chat testing |

```powershell
# Auto-discover mode (zero args) — works in ANY Purview tenant. Discovers
# tenant ID, primary domain, and 2 licensed users from Microsoft Graph.
# Share this one command with your team — they just clone and run.
./scripts/Invoke-SmokeTest.ps1

# Auto-discover + Insider Risk burst activity
./scripts/Invoke-SmokeTest.ps1 -BurstActivity

# Config mode — targeted test cases derived from a deployed lab profile
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic-lab -Cloud commercial

# Validate DLP matches in audit log
./scripts/Invoke-SmokeTest.ps1 -ValidateOnly -Since (Get-Date).AddHours(-1)

# Dry run
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic-lab -SkipAuth -WhatIf
```

A GitHub Actions workflow runs smoke tests daily at 10 AM ET on weekdays (`.github/workflows/daily-smoke-test.yml`). Requires OIDC setup — see below.

### OIDC setup for daily smoke tests

The daily workflow uses OIDC federated credentials. To set up:

1. **Create an app registration** in Entra ID with these application permissions:
   - `Mail.Send` (send test emails)
   - `Files.ReadWrite.All` (upload to OneDrive)
   - `Sites.ReadWrite.All` (SharePoint access)
   - `User.Read.All` (resolve users)

2. **Add a federated credential** for GitHub Actions:
   - Issuer: `https://token.actions.githubusercontent.com`
   - Subject: `repo:chashea/purview-lab-deployer:environment:commercial`
   - Audience: `api://AzureADTokenExchange`

3. **Set repository secrets**:
   - `AZURE_TENANT_ID` — your Entra ID tenant ID
   - `AZURE_CLIENT_ID` — the app registration client ID
   - `AZURE_DOMAIN` — your tenant domain (e.g., `contoso.onmicrosoft.com`)

4. **Create a GitHub environment** named `commercial` in repo settings.

## Additional docs

- **[Quick Start Guide](QUICKSTART.md)** — get running in your tenant in 30 minutes
- [Commercial config guide](configs/commercial/README.md)
- [GCC config guide](configs/gcc/README.md)
- [Profiles overview](profiles/README.md)
