# Purview → Sentinel Integration Lab (Commercial)

Stream Microsoft Purview DLP, Insider Risk Management, and sensitivity-label signals into a Microsoft Sentinel workspace. Ship analytics rules, a workbook, and an IRM auto-triage playbook end-to-end from one config file.

> **Microsoft Sentinel portal shift:** New Sentinel customers onboarded after **July 1, 2025** are auto-onboarded to the Microsoft Defender portal. Microsoft Sentinel in the Azure portal retires **March 31, 2027**. This lab's Azure artifacts work in both portals — RUNBOOK calls out the Defender portal path.

## Prerequisites

1. **Microsoft 365 E5** (or E5 Compliance add-on) for Purview
2. **Azure subscription** with **Owner** or **Contributor** on the subscription (the only Purview lab profile that provisions Azure resources)
3. **Azure CLI** (`az`) signed in via `az login`
4. **PowerShell 7+** (`pwsh --version` returns 7.x)
5. **Insider Risk SIEM export** turned on in the Purview portal (Settings → Insider Risk Management → Export alerts)
6. **Defender XDR tenant admin consent** for the connector (required — see RUNBOOK)

## Getting the repository

```bash
git clone https://github.com/chashea/purview-lab-deployer.git
cd purview-lab-deployer
```

## Deploy the Sentinel lab

```powershell
az login
az account set --subscription <subscription-guid>

./Deploy-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel `
    -TenantId <tenant-guid> -SubscriptionId <subscription-guid>
```

The `-SubscriptionId` parameter (or `PURVIEW_SUBSCRIPTION_ID` environment variable) is required — the config ships with an empty value so the repo doesn't carry hardcoded tenant-specific GUIDs.

### Optional variations

```powershell
# Preview (no Azure mutations, no az login required)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel -WhatIf

# Skip test users (use your own licensed accounts)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel -TenantId <tenant> -SubscriptionId <sub> -SkipTestUsers

# Teardown (non-destructive by default — removes child resources only)
./Remove-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel `
    -ManifestPath ./manifests/commercial/PVSentinel_<timestamp>.json `
    -SubscriptionId <subscription-guid>

# Teardown AND delete resource group (safety-gated; see RUNBOOK)
./Remove-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel `
    -ManifestPath ./manifests/commercial/PVSentinel_<timestamp>.json `
    -SubscriptionId <subscription-guid> -ForceDeleteResourceGroup
```

### Post-deploy readiness check

```powershell
./scripts/Test-SentinelReady.ps1 -LabProfile purview-sentinel -Cloud commercial `
    -SubscriptionId <subscription-guid>
```

Exit codes: `0` = ready, `1` = wait (connectors still warming up), `2` = blocked (missing workspace, connectors, or rules). For deeper verification run `./scripts/Test-SentinelLab.ps1 -ConfigPath ./configs/commercial/purview-sentinel-demo.json`.

## Scope

- **Config:** `configs/commercial/purview-sentinel-demo.json`
- **Prefix:** `PVSentinel`
- **Cloud:** commercial
- **Azure resources:** resource group + Log Analytics workspace + Sentinel onboarding + connectors + rules + workbook + playbook

## What gets deployed

### Azure resources

| Resource | Name | Notes |
|---|---|---|
| Resource group | `PVSentinel-rg` | Tagged `createdBy=purview-lab-deployer` for safe teardown |
| Log Analytics workspace | `PVSentinel-ws` | PerGB2018 SKU, 30-day analytics retention |
| Sentinel onboarding | (on workspace) | Enables Sentinel over the workspace |
| Content Hub solutions | Microsoft Defender XDR, Microsoft Purview Insider Risk Management, Microsoft 365 | Installed so connector cards appear in the Sentinel portal |
| Data connectors | 3 (see below) | Per MS Learn Microsoft.SecurityInsights/dataConnectors (2025-07-01-preview) |
| Analytics rules | 4 scheduled | Purview-sourced alerts |
| Workbook | Purview Signals | Visualizes DLP + IRM + label volume |
| Logic App playbook | IRM auto-triage | Incident-triggered enrichment + comment |
| Automation rule | IRM auto-triage | Wires IRM high-severity incidents to the playbook |

### Data connectors

| Connector | ARM kind | Produces |
|---|---|---|
| Microsoft Defender XDR | `MicrosoftThreatProtection` | Incidents + alerts (including DLP via the XDR pipeline) |
| Microsoft 365 Insider Risk Management | `OfficeIRM` | `SecurityAlert` rows for IRM high-severity alerts |
| Office 365 | `Office365` | `OfficeActivity` (Exchange, SharePoint, Teams audit) |

> **Connector kind correction (2026-04 update):** Earlier lab versions used `MicrosoftPurviewInformationProtection` for the IRM connector. That kind is for the Information Protection connector — a different product. The correct kind per MS Learn is `OfficeIRM`.

### Analytics rules

| Rule | Source | Severity | Tactic |
|---|---|---|---|
| `PVSentinel-HighSevDLP` | Defender XDR `SecurityAlert` | High | Exfiltration |
| `PVSentinel-IRMHighSev` | OfficeIRM `SecurityAlert` | High | Exfiltration |
| `PVSentinel-LabelDowngrade` | `OfficeActivity` (`SensitivityLabelUpdated` + downgrade heuristic) | Medium | ImpairProcessControl |
| `PVSentinel-MassDownloadAfterDLP` | Cross-table: DLP match then mass download | High | Exfiltration |

### Workbook

Single "Purview Signals" workbook with panels for DLP volume, IRM severity breakdown, label movement, and top alerting policies.

### Playbook

`PVSentinel-IRM-AutoTriage` — Logic App triggered by Sentinel incidents. Managed identity gets Microsoft Sentinel Responder on the workspace; Sentinel first-party app gets Logic App Contributor on the resource group. On an IRM high-severity incident it appends an enrichment comment with initial triage guidance.

### Test data

One email (`rtorres → jblake`) with embedded SSN to seed the DLP → Defender XDR → Sentinel `SecurityAlert` flow.

## Post-deploy steps

1. **Run the readiness check** — `./scripts/Test-SentinelReady.ps1 -LabProfile purview-sentinel -Cloud commercial -SubscriptionId <sub>`.
2. **Grant Defender XDR tenant admin consent** — Sentinel portal → Data connectors → Microsoft Defender XDR → Connect (requires tenant admin). This enables the connector's data flow even though the Content Hub solution is already installed.
3. **Enable Insider Risk SIEM export** — Purview portal → Settings → Insider Risk Management → Export alerts → On.
4. **Optional: Onboard workspace to Defender portal** — Microsoft's recommended path per MS Learn. See RUNBOOK.
5. **Optional: Install the Microsoft Purview Content Hub solution** — ships Microsoft-maintained analytics rules (`Sensitive Data Discovered in the Last 24 Hours`) and workbook complementing this lab's custom rules. See RUNBOOK.

## References

- [MS Learn: Integrate Microsoft Sentinel and Microsoft Purview](https://learn.microsoft.com/azure/sentinel/purview-solution)
- [MS Learn: Microsoft Sentinel in the Microsoft Defender portal](https://learn.microsoft.com/azure/sentinel/microsoft-sentinel-defender-portal)
- [MS Learn: Microsoft 365 Insider Risk Management connector](https://learn.microsoft.com/azure/sentinel/data-connectors-reference#microsoft-365-insider-risk-management-irm-preview)
- [MS Learn: IRM SIEM export guidance](https://learn.microsoft.com/purview/insider-risk-management-settings-share-data)
- [MS Learn: Microsoft.SecurityInsights/dataConnectors ARM schema (2025-07-01-preview)](https://learn.microsoft.com/azure/templates/microsoft.securityinsights/2025-07-01-preview/dataconnectors)

## Validation

- Deploy runs ARM-based provisioning, Content Hub solution installs, and connector creation
- `Test-SentinelReady.ps1` — pre-demo gate (workspace, connectors, rules, recent data)
- `Test-SentinelLab.ps1` — deep smoke test covering entity mappings, playbook wiring, automation rules
- Pester tests cover config shape (`Invoke-Pester tests/`)
- Teardown is safety-gated: resource group deletion requires manifest + tag match + explicit `-ForceDeleteResourceGroup`
