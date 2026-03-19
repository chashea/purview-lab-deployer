# purview-lab-deployer

Config-driven Microsoft Purview demo lab deployment. PowerShell 7+, modular by workload, deploy and teardown symmetry.

## Deployment profiles

| Profile | Description | Guide |
|---------|-------------|-------|
| **basic-lab** | Core compliance workloads (DLP, labels, retention, eDiscovery, insider risk) | [profiles/commercial/basic-lab/README.md](profiles/commercial/basic-lab/README.md) |
| **shadow-ai** | Shadow AI detection and governance (AI app blocking, discovery, session monitoring) | [profiles/commercial/shadow-ai/README.md](profiles/commercial/shadow-ai/README.md) |

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
| CustomSensitiveInfoTypes | Full | Custom SIT patterns |
| SensitivityLabels | Full | Labels and auto-label policies |
| DLP | Full | Policies and rules with enforcement config |
| Retention | Full | Retention policies |
| EDiscovery | Full | Cases, custodians, holds, searches |
| CommunicationCompliance | Full | Supervision policies |
| InsiderRisk | Full | Insider risk management policies |
| ConditionalAccess | Full | CA policies (report-only mode) |
| AppGovernance | Hybrid | MDCA app tagging + discovery/session policies via API; OAuth governance is manual |
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
```

## Supported clouds

| Cloud | Configs | Notes |
|-------|---------|-------|
| **commercial** | `configs/commercial/` | Full feature support |
| **gcc** | `configs/gcc/` | Some workloads limited — see `profiles/gcc/capabilities.json` |

## Additional docs

- [Commercial config guide](configs/commercial/README.md)
- [GCC config guide](configs/gcc/README.md)
- [Profiles overview](profiles/README.md)
