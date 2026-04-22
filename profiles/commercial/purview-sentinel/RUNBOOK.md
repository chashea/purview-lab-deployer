# Purview → Sentinel Lab — Post-Deploy Runbook (Commercial)

Post-deployment steps and demo-day preparation.

## Prerequisites

- Subscription **Owner** or **Contributor** (for resource group + Sentinel onboarding)
- Microsoft Sentinel **Contributor** role on the workspace (for connector + rule management)
- Microsoft 365 **Global Admin** or **Security Administrator** (for Defender XDR connector consent)
- Microsoft 365 **Insider Risk Management Admin** or **Compliance Admin** (for IRM settings)

---

## 1. Run the readiness check

```powershell
./scripts/Test-SentinelReady.ps1 -LabProfile purview-sentinel -Cloud commercial `
    -SubscriptionId <subscription-guid>
```

Green across the board = demo-ready. Each red/yellow item is surfaced with a remediation hint.

Deeper end-to-end test (non-blocking on partial readiness):

```powershell
./scripts/Test-SentinelLab.ps1 -ConfigPath ./configs/commercial/purview-sentinel-demo.json
```

This verifies entity mappings, playbook wiring, automation rule linkage, and Content Hub solution state.

---

## 2. Grant Defender XDR connector consent

The deployment installs the Microsoft Defender XDR solution from Content Hub and provisions the connector resource, but the connector's actual data flow requires tenant admin consent on top:

1. Open **Microsoft Sentinel** → **Data connectors** → search for **Microsoft Defender XDR**
2. Select the connector → **Open connector page**
3. Under **Configuration**, select **Connect incidents & alerts**
4. Keep **Turn off all Microsoft incident creation rules for these products** selected (so Defender XDR becomes the authoritative source for M365 alerts in Sentinel)
5. Apply changes

Without this step, `SecurityAlert` rows from DLP won't flow. The readiness script catches this by checking for recent rows.

---

## 3. Enable Insider Risk Management SIEM export

IRM alerts won't appear in Sentinel without SIEM export turned on:

1. Microsoft Purview portal → **Settings** → **Insider Risk Management** → **Export alerts**
2. Turn the setting **On**

IRM alerts reach Sentinel via the Office 365 Management Activity API pipeline. Allow 60 minutes for the first batch of alerts to arrive after enabling.

> **Automation caveat:** Per MS Learn, IRM incidents in the Defender portal have no alert content by default. If you plan automation on Sentinel incidents derived from IRM, turn off data sharing in IRM settings (or ensure your automation handles the no-alert case).

---

## 4. Optional: Onboard the workspace to the Microsoft Defender portal

Microsoft's recommended SIEM experience as of mid-2025. New customers after July 1, 2025 auto-onboard; existing customers can opt in.

1. Sign in to [security.microsoft.com](https://security.microsoft.com)
2. Navigate to **Microsoft Sentinel** → **Configurations** → (follow prompt to connect workspace)
3. Select `PVSentinel-ws`
4. Confirm onboarding — this connects the Azure workspace to the Defender portal unified experience
5. After onboarding, all the rules, workbooks, and connectors you deployed appear in the Defender portal alongside Defender XDR signals

> **Azure portal retirement:** Microsoft Sentinel in the Azure portal retires March 31, 2027. Plan the transition now. The lab's artifacts are portable — no config changes needed.

---

## 5. Optional: Install the Microsoft Purview Content Hub solution

This lab ships custom analytics rules tuned for the demo. Microsoft's official "Microsoft Purview" Content Hub solution ships complementary rules (including **Sensitive Data Discovered in the Last 24 Hours** and its customized variant) that query the `PurviewDataSensitivityLogs` table.

1. Sentinel portal → **Content Hub** (or Defender portal → Sentinel → **Content management** → **Content hub**)
2. Search for **Microsoft Purview**
3. Select the solution → **Install**
4. After install, enable the analytics rule templates you want (all ship disabled by default):
   - **Sensitive Data Discovered in the Last 24 Hours** — generic detection across all classifications
   - **Sensitive Data Discovered in the Last 24 Hours - Customized** — tuned for specific classifications (SSN, PHI, etc.)

For the customized rule, edit the `| where` clause in the Rule query to match the [supported data fields](https://learn.microsoft.com/azure/azure-monitor/reference/tables/purviewdatasensitivitylogs) on `PurviewDataSensitivityLogs`. Pair with this lab's custom rules for full DLP + classification coverage.

---

## 6. Optional: Configure Sentinel data lake tier

Sentinel data lake (GA July 2025) separates analytics and lake storage tiers. High-volume tables benefit from lake-tier placement (cheaper, longer retention) while low-volume alert tables stay in the analytics tier.

Candidate split for this lab:

| Table | Recommended tier | Why |
|---|---|---|
| `SecurityAlert` | Analytics | Low volume, needed for real-time rules |
| `OfficeActivity` | Split (analytics + lake) | High volume, rules need recent data, compliance needs long retention |
| `DeviceEvents` | Lake | If shadow-ai or device-DLP signals flow here, volume is high |
| `PurviewDataSensitivityLogs` | Analytics | Low to medium volume, used by Microsoft Purview solution rules |

Configure per-table via: **Defender portal → Settings → Microsoft Sentinel → Tables** (or **Azure portal → Sentinel workspace → Settings → Tables**).

The lab config exposes this as `workloads.sentinelIntegration.tableTiers` — currently informational; automation is a future enhancement.

---

## 7. Seed alerts before a live demo

Empty dashboards read as "nothing's working." Seed 30-60 min before demo:

```powershell
# Send test emails with SSN patterns to trigger DLP rules
./scripts/Invoke-SmokeTest.ps1 -ConfigPath ./configs/commercial/purview-sentinel-demo.json
```

Or manually:
- Send an email from a test user containing an SSN → triggers DLP → Defender XDR `SecurityAlert` → Sentinel `PVSentinel-HighSevDLP` rule
- Downgrade a sensitivity label on a SharePoint file → triggers Sentinel `PVSentinel-LabelDowngrade` rule

Allow ~30 min for the signal pipeline end-to-end.

---

## 8. Teardown verification

Teardown is **safety-gated** — this is the only lab profile that can delete Azure subscription resources.

### Non-destructive teardown (default)

Removes Sentinel child resources (rules, workbooks, connectors, playbook) but **preserves** the resource group and workspace so you can redeploy quickly:

```powershell
./Remove-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel `
    -ManifestPath ./manifests/commercial/PVSentinel_<timestamp>.json `
    -SubscriptionId <subscription-guid>
```

### Destructive teardown (deletes resource group)

Requires ALL of the following to succeed:

- `-ForceDeleteResourceGroup` switch explicitly passed
- `-ManifestPath` pointing at a deployment manifest
- Manifest has `createdResourceGroup: true`
- Resource group tags include `createdBy=purview-lab-deployer`
- Resource group name + subscription match the manifest exactly

```powershell
./Remove-Lab.ps1 -Cloud commercial -LabProfile purview-sentinel `
    -ManifestPath ./manifests/commercial/PVSentinel_<timestamp>.json `
    -SubscriptionId <subscription-guid> `
    -ForceDeleteResourceGroup
```

If any gate fails, the teardown script logs the reason and refuses the delete. This prevents accidentally nuking a shared resource group the lab was deployed into.

### Verify clean teardown

```bash
az resource list --resource-group PVSentinel-rg --subscription <sub> --output table
```

Should return empty after destructive teardown. After non-destructive teardown, the workspace + Sentinel onboarding remain.

---

## Verification checklist

- [ ] `Test-SentinelReady.ps1` returns READY
- [ ] Defender XDR connector consented (step 2)
- [ ] IRM SIEM export toggled on (step 3)
- [ ] `SecurityAlert` rows present in workspace (query: `SecurityAlert | take 10`)
- [ ] `OfficeActivity` rows present (query: `OfficeActivity | take 10`)
- [ ] All 4 analytics rules enabled and status = Active
- [ ] Workbook rendered in Sentinel workbooks list
- [ ] Playbook + automation rule visible under `PVSentinel-` prefix
- [ ] (Optional) Microsoft Purview Content Hub solution installed (step 5)
- [ ] (Optional) Workspace onboarded to Defender portal (step 4)
- [ ] Seed alerts generated before demo (step 7)

---

## Common issues

### "No SecurityAlert rows in workspace"

- Defender XDR connector hasn't been consented (step 2)
- IRM SIEM export isn't enabled (step 3)
- First-run lag: 60-90 min from deploy to first alert

### "Connector cards missing in Sentinel portal"

- Content Hub solution installs may have failed — rerun Deploy-Lab.ps1 (idempotent)
- Check `SolutionsInstallation` state via `az rest`

### "Playbook fires but incident comment doesn't appear"

- Logic App managed identity missing Microsoft Sentinel Responder role on workspace — re-run Deploy-Lab.ps1 to re-grant
- Sentinel first-party app missing Logic App Contributor on resource group

### "`-ForceDeleteResourceGroup` refused the delete"

- Read the log — each gate failure is explained. Most common: manifest mismatch (ran Deploy-Lab twice and using the wrong manifest).
