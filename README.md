![Validate PowerShell](https://github.com/chashea/purview-lab-deployer/actions/workflows/validate.yml/badge.svg)
![GitHub release](https://img.shields.io/github/v/release/chashea/purview-lab-deployer)

# purview-lab-deployer

Config-driven Microsoft Purview demo lab deployment. PowerShell 7+, modular by workload, deploy and teardown symmetry.

## Deployment profiles

| Profile | Description | Guide |
|---------|-------------|-------|
| **basic** | Core compliance workloads: OneDrive/Teams/Outlook/SharePoint DLP, sensitivity labels, retention, eDiscovery, insider risk, audit config. Prefix `PVLab`. | [profiles/commercial/basic/README.md](profiles/commercial/basic/README.md) |
| **ai** | Copilot + gen-AI governance: Copilot DLP, Shadow AI detection (Endpoint/Browser/Network), AI-specific labels, IRM, Sentinel integration, cross-signal correlation. Prefix `PVAI`. | [profiles/commercial/ai/README.md](profiles/commercial/ai/README.md) |
| **purview-sentinel** | Send Purview DLP / Insider Risk / sensitivity-label signals into a Microsoft Sentinel workspace (Log Analytics + data connectors + analytics rules + workbook). Requires an Azure subscription. | [profiles/commercial/purview-sentinel/README.md](profiles/commercial/purview-sentinel/README.md) |

Each profile is a self-contained deployment with its own prefix, config, and lifecycle. See the profile README for setup instructions.

**Deprecated aliases** — the following names are still accepted and emit a deprecation warning at runtime:

| Deprecated name | Resolves to |
|-----------------|-------------|
| `basic-lab` | `basic` |
| `shadow-ai` | `ai` |
| `copilot-dlp` | `ai` |
| `copilot-protection` | `ai` |
| `ai-security` | `ai` |

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

### Additional prerequisites for `purview-sentinel` and `ai`

The `purview-sentinel` and `ai` profiles provision Azure subscription resources
(resource group, Log Analytics workspace, Sentinel).

- Azure subscription + **Owner** or (**Contributor** + **User Access
  Administrator**) on the target subscription
- Azure CLI 2.50+ on PATH (`az --version`)
- `az login` into the tenant that owns the subscription and
  `az account set --subscription <id>` before running
- Providers registered: `Microsoft.OperationalInsights`, `Microsoft.SecurityInsights`
  (run `az provider register --namespace <ns>` if needed)
- Pass `-SubscriptionId <guid>` to `Deploy-Lab.ps1` (or set `PURVIEW_SUBSCRIPTION_ID`).
  The config ships with an empty subscription ID — no tenant-specific GUIDs in the repo.

> **Defender portal transition (MS Learn):** New Sentinel customers onboarded after **July 1, 2025** are auto-onboarded to the Microsoft Defender portal. Microsoft Sentinel in the Azure portal retires **March 31, 2027**. The lab's artifacts deploy via ARM and work in both portals — onboard the workspace to the Defender portal to use the unified SecOps experience.

**Content Hub solutions (auto-installed).** The Defender XDR and Purview
Insider Risk Management data connectors cannot be provisioned by a direct ARM
`PUT /dataConnectors` — Microsoft Sentinel routes them through Content Hub
solution installs. The deployment script performs the full 3-step install the
portal does: lists the Content Hub catalog, fetches each solution's
`packagedContent` ARM template, registers the package via
`Microsoft.SecurityInsights/contentPackages`, then submits the packagedContent
deployment so the connector card, hunting queries, analytics-rule templates,
workbooks, and playbooks all materialize as `contentTemplates`. After this
runs the connector cards are visible in the Sentinel **Data connectors**
blade.

What still requires a manual step (tenant-side consent, not ARM-configurable):

1. **Microsoft Defender XDR connector** — Sentinel portal → **Data connectors**
   → *Microsoft Defender XDR* → **Connect** (requires tenant admin consent).
2. **Microsoft Purview Insider Risk Management connector** — (a) Purview portal
   → *Insider risk management → Settings → Export alerts* → enable SIEM export,
   then (b) Sentinel portal → **Data connectors** → *Microsoft Purview Insider
   Risk Management* → **Connect**.

The deployment log prints the exact remediation string for each after the
Content Hub install succeeds.

Tenant-side caveat (not ARM-configurable): to receive **Insider Risk
Management** alerts in Sentinel, enable *SIEM export* in the Microsoft Purview
portal under **Insider risk management → Settings → Export alerts**. The
deployment will emit a warning reminder after provisioning.

The Microsoft Purview (Azure) data-sensitivity product is a separate service
and is out of scope for this lab — the `purview-sentinel` profile targets
Microsoft Purview (M365) compliance signals only.

### Additional prerequisites for the `ai` profile

The `ai` profile covers Copilot DLP + Shadow AI + Sentinel under one `PVAI`
prefix. It has the same Azure/Sentinel prerequisites as `purview-sentinel`
plus the following:

- **Microsoft 365 Copilot licenses** for demo users (the Copilot DLP guardrails
  only produce signal if users can actually use Copilot). Deploy-Lab prints a
  preflight warning if demo users are missing the SKU.
- **Microsoft Defender for Endpoint** onboarded on at least one test device —
  required for Endpoint DLP paste/upload blocks on external AI sites (ChatGPT,
  Claude, Gemini, etc.) to fire live during demos.
- After deploy, run `./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -Apply` to
  merge the AI-site domain list into the tenant's shared Endpoint DLP global
  settings. Preview first — this touches tenant-wide settings.
- Pre-demo readiness: run `Test-CopilotDlpReady.ps1`, `Test-ShadowAiReady.ps1`,
  and `Test-SentinelReady.ps1` against the unified config. Each gives a
  per-surface READY/WAIT/BLOCKED verdict.
- Known manual portal step: the Copilot **Prompt SIT** DLP rules (SSN, Credit
  Card, PHI) fail ARM creation with
  `ErrorMissingRestrictActionForCopilotException` — the correct
  `-RestrictAccess` value is undocumented for SIT+Copilot. The deployer logs
  a warning and moves on; configure in the Purview portal if you need live
  prompt-SIT enforcement.

## Quick start

```powershell
git clone https://github.com/chashea/purview-lab-deployer.git
cd purview-lab-deployer

# Interactive (prompts for cloud, profile, tenant)
./Deploy-Lab-Interactive.ps1

# Or specify directly
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic -TenantId <tenant-guid>

# Bring your own pre-licensed tenant users (overrides the users in the config)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic -TestUsers alice@contoso.com,bob@contoso.com

# AI governance lab (Copilot DLP + Shadow AI + Sentinel under one prefix)
az login
az account set --subscription <subscription-id>
./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai -SubscriptionId <subscription-id>

# Sentinel integration lab (requires an Azure subscription — see prerequisites above)
az login
az account set --subscription <subscription-id>
./Deploy-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel

# Tear down Sentinel lab (non-destructive by default; child resources only)
./Remove-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel -ManifestPath ./manifests/commercial/<name>.json

# Tear down AND delete the Sentinel resource group (only if the module created it and tags match)
./Remove-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel -ManifestPath ./manifests/commercial/<name>.json -ForceDeleteResourceGroup

# Verify a deployed Sentinel lab end-to-end (read-only; exits non-zero on failure)
pwsh ./scripts/Test-SentinelLab.ps1 -ConfigPath ./configs/commercial/purview-sentinel-demo.json

# Post-deploy readiness checks for the ai profile
./scripts/Test-CopilotDlpReady.ps1 -ConfigPath ./configs/commercial/ai-demo.json -Cloud commercial
./scripts/Test-ShadowAiReady.ps1   -ConfigPath ./configs/commercial/ai-demo.json -Cloud commercial
./scripts/Test-SentinelReady.ps1   -ConfigPath ./configs/commercial/ai-demo.json -Cloud commercial -SubscriptionId <sub>

# Push Endpoint DLP AI domain block list (tenant-wide; preview first, then Apply)
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -ConfigPath ./configs/commercial/ai-demo.json
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -ConfigPath ./configs/commercial/ai-demo.json -Apply
```

### What the Sentinel lab builds

Beyond the workspace + data connectors + analytics rules + workbook, the
deployer also wires up investigation hygiene for you:

- **Entity mappings & incident grouping** — all four analytics rules project
  Account (and, for the sensitivity-label-downgrade rule, IP and File)
  entities. A grouping configuration collapses alerts for the same Account
  within a 5-hour window into a single incident, so a burst of DLP/IRM
  activity from one user shows as one investigation item, not four.
- **IRM auto-triage playbook** — a Logic App (`PVSentinel-IRM-AutoTriage`)
  with a Microsoft Sentinel incident trigger, a system-assigned managed
  identity, and an `azuresentinel` API connection. When the IRM high-severity
  analytics rule fires, an automation rule runs the playbook, which posts an
  enrichment comment to the incident with recommended next steps.
- **RBAC wiring** — the deployer automatically grants the playbook MSI the
  *Microsoft Sentinel Responder* role on the workspace and grants the Sentinel
  first-party app *Logic App Contributor* on the resource group so the
  automation rule is permitted to invoke the playbook.
- **Smoke test** — `scripts/Test-SentinelLab.ps1` verifies the workspace,
  Sentinel onboarding, expected connectors (live or installed via Content
  Hub), every analytics rule (including that entity mappings are present),
  the workbook, the playbook, and the automation rule. Suitable for CI.

### What the AI lab adds on top of Sentinel

The `ai` profile unifies Copilot DLP + Shadow AI + `purview-sentinel` into a single deployment under prefix `PVAI`. Additions beyond the Sentinel profile:

- **Copilot DLP** — label-based block rule for files tagged `Highly Confidential > AI Blocked from External Tools` / `AI Regulated Data`; Copilot Prompt SIT Block policy scaffold (rules need manual portal config per the prereq caveat).
- **Shadow AI DLP** — 3 policies across Devices (Endpoint DLP paste/upload block), Browser (Edge for Business inline prompt inspection), Network (SASE/SSE), each risk-tiered by Insider Risk score.
- **Unified sensitivity-label taxonomy** — 2 parents + 10 AI-specific sublabels (AI Internal Use, AI Restricted Recipients, AI Blocked from External Tools, AI Regulated Data × Confidential and Highly Confidential).
- **3 AI-specific Sentinel analytics rules** (on top of the 4 already shipped by `purview-sentinel`): `CopilotDLPPromptBlock`, `ShadowAIPasteUpload`, `RiskyAIUsageCorrel` (cross-table join of IRM Risky-AI alerts with DLP blocks on AI surfaces in the same 4-hour window).
- **Second Sentinel workbook** — `AI Risk Signals` with panels for Copilot DLP blocks, Shadow AI paste attempts by target AI site, Risky AI usage IRM alerts, and cross-signal users.
- **Microsoft Purview Content Hub solution** — auto-installed alongside Defender XDR + IRM + Microsoft 365, giving you the MS-maintained `PurviewDataSensitivityLogs` analytics rules alongside this lab's custom ones.
- **3 IRM policies** using `Risky AI usage`, `Data leaks`, and `Data theft by departing users` templates, scoped to **All users and groups**.
- **5 retention policies** including three AI-Applications-scoped ones: `MicrosoftCopilotExperiences`, `EnterpriseAIApps`, `OtherAIApps`.
- **Test data** — 5 OneDrive documents auto-labeled at deploy via Graph `assignSensitivityLabel`, seeding the label-based Copilot block demo.

Use the `ai` profile when a single demo needs to cover the full integrated narrative — Copilot DLP + Shadow AI + Sentinel with cross-signal correlation. Use `basic` for compliance-baseline audiences and `purview-sentinel` for SOC-focused demos.

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
| `copilot-test-prompts.md` | Copy-paste prompts for M365 Copilot Chat — SSN/CC/PHI, labeled-file scenarios, subtlety tests, clean control prompts |
| `shadow-ai-test-prompts.md` | Copy-paste prompts targeting external AI sites (ChatGPT, Claude, Gemini, etc.) for Endpoint/Browser/Network DLP + IRM escalation flow |
| `Test-CopilotDlpReady.ps1` | Pre-demo readiness gate — validates Copilot DLP policies, labels, licenses (exit codes 0/1/2) |
| `Test-ShadowAiReady.ps1` | Pre-demo readiness gate — validates Shadow AI DLP policies, IRM, Endpoint DLP domain list |
| `Test-SentinelReady.ps1` | Pre-demo readiness gate for the Sentinel stack — workspace, connectors, rules, 24h data-flow check |
| `Test-SentinelLab.ps1` | Deep end-to-end smoke test for a deployed Sentinel lab (CI-grade) |
| `Set-ShadowAiEndpointDlpDomains.ps1` | Push AI-site block list to tenant-wide Endpoint DLP global settings (discover → `-Apply`) |

```powershell
# Auto-discover mode (zero args) — works in ANY Purview tenant. Discovers
# tenant ID, primary domain, and 2 licensed users from Microsoft Graph.
# Share this one command with your team — they just clone and run.
./scripts/Invoke-SmokeTest.ps1

# Auto-discover + Insider Risk burst activity
./scripts/Invoke-SmokeTest.ps1 -BurstActivity

# Config mode — targeted test cases derived from a deployed lab profile
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -Cloud commercial

# Validate DLP matches in audit log
./scripts/Invoke-SmokeTest.ps1 -ValidateOnly -Since (Get-Date).AddHours(-1)

# Dry run
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -SkipAuth -WhatIf
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
