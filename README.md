![Validate PowerShell](https://github.com/chashea/purview-lab-deployer/actions/workflows/validate.yml/badge.svg)
![GitHub release](https://img.shields.io/github/v/release/chashea/purview-lab-deployer)

# purview-lab-deployer

Config-driven Microsoft Purview demo lab deployment. PowerShell 7+, modular by workload, deploy and teardown symmetry.

## Deployment profiles

| Profile | Description | Guide |
|---------|-------------|-------|
| **basic-lab** | Core compliance workloads (DLP, labels, retention, eDiscovery, insider risk) | [profiles/commercial/basic-lab/README.md](profiles/commercial/basic-lab/README.md) |
| **basic-lab-existing** | Same as basic-lab, using pre-licensed tenant users (no user creation) | [configs/commercial/README.md](configs/commercial/README.md) |
| **shadow-ai** | Shadow AI detection and governance (AI app blocking, discovery, session monitoring) | [profiles/commercial/shadow-ai/README.md](profiles/commercial/shadow-ai/README.md) |
| **shadow-ai-existing** | Same as shadow-ai, remapped to pre-licensed tenant users | [configs/commercial/README.md](configs/commercial/README.md) |
| **copilot-protection** | Copilot DLP guardrails for Copilot + Copilot Chat (prompt blocking, labeled content protection, web-search boundaries, audit evidence) | [profiles/commercial/copilot-dlp/README.md](profiles/commercial/copilot-dlp/README.md) |

Each profile is a self-contained deployment with its own prefix, config, and lifecycle. See the profile README for setup instructions.

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

## Quick start

```powershell
git clone https://github.com/chashea/purview-lab-deployer.git
cd purview-lab-deployer

# Interactive (prompts for cloud, profile, tenant)
./Deploy-Lab-Interactive.ps1

# Or specify directly
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -TenantId <tenant-guid>

# Use existing licensed users (skips user creation, test data emails deliver reliably)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic-lab-existing
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai-existing
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
# Run smoke test (sends emails + uploads files)
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic-lab -Cloud commercial

# Validate DLP matches in audit log
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic-lab -ValidateOnly -Since (Get-Date).AddHours(-1)

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

- [Commercial config guide](configs/commercial/README.md)
- [GCC config guide](configs/gcc/README.md)
- [Profiles overview](profiles/README.md)
