# Copilot DLP Guardrails — Post-Deploy Runbook (GCC)

Complete these steps after running `Deploy-Lab.ps1` to prepare the full demo experience.

> **GCC Note:** Feature rollout for Copilot DLP may lag behind commercial. If any step references a feature not yet available in your GCC tenant, note it in the demo as "coming to GCC" and proceed with the remaining phases.

> **GCC Limitation — No SIT-Based Copilot DLP:** In GCC, you cannot create a DLP policy targeting Microsoft 365 Copilot with Sensitive Information Type (SIT) conditions in the rules. Only label-based rules are supported for Copilot DLP in GCC. This runbook covers label-based content blocking only. SIT-based Copilot prompt blocking is available in commercial tenants.

---

## Pre-Flight: Validate GCC Feature Availability

Run the automated readiness check — it verifies policies, labels, publishing, and Copilot licenses in one pass:

```powershell
./scripts/Test-CopilotDlpReady.ps1 -LabProfile copilot-protection -Cloud gcc
```

If the script is not an option, manual spot-checks:

```powershell
# 1. DLP cmdlets accept the GA Copilot location parameters
(Get-Command New-DlpCompliancePolicy).Parameters.Keys -contains 'Locations'
(Get-Command New-DlpCompliancePolicy).Parameters.Keys -contains 'EnforcementPlanes'

# 2. CopilotInteraction audit events
Search-UnifiedAuditLog -Operations CopilotInteraction -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -ResultSize 1

# 3. Sensitivity labels published
Get-Label | Where-Object { $_.DisplayName -like 'PVCopilotDLP*' }
```

| Check | Expected | If Missing |
|---|---|---|
| `Locations` + `EnforcementPlanes` params | both `True` | Copilot location skipped — add manually in portal when feature rolls out to GCC |
| CopilotInteraction audit | Results or "no results" (not an error) | Copilot audit not yet enabled — Phase 2 audit demos will rely on DlpRuleMatch only |
| Published labels | PVCopilotDLP labels listed | Labels need time to publish — wait 15–30 minutes after deploy |

---

## Phase 0 — Baseline Demo (Manual, 5 min)

The baseline creates the before/after contrast. Show Copilot working without guardrails **before** DLP policies take effect.

> DLP policies deploy in simulation mode and can take up to 4 hours to fully propagate. Use this window for the baseline demo and set expectations with the audience.

### Steps

1. **Open Microsoft 365 Copilot** (copilot.microsoft.com or in-app)
2. **Ask Copilot to summarize a document** — use an unlabeled file on SharePoint
3. **Ask Copilot a question that references file content** — confirm it can reason over files
4. **Ask Copilot a general question** — confirm web-backed responses work

### Key Message

> "This is Copilot with no guardrails. It can summarize anything, search anything, and answer anything. Now let's put it inside the guardrails."

---

## Phase 1 — Verify Label-Based Blocking (Automated)

### Pre-Demo File Labeling

Documents are uploaded to the owner's OneDrive and labeled automatically during deployment via the Microsoft Graph `assignSensitivityLabel` API. The SSN auto-label policy also catches sensitive content.

| File | Owner | Label applied at deploy |
|---|---|---|
| `Q4-Revenue-Forecast.txt` | mtorres | Highly Confidential > Restricted |
| `Employee-Benefits-Summary.txt` | mtorres | Highly Confidential > Regulated Data |
| `Patient-Intake-Notes.txt` | jkim | Unlabeled (for before/after contrast) |

**GCC note:** Microsoft Graph's `assignSensitivityLabel` is documented as unavailable in US Government L4 and L5 (GCC High/DoD) tenants. On commercial GCC (Moderate), the call may still succeed. If the deploy log shows a `403` or "not available" warning, apply the labels manually via OneDrive web UI for the demo.

### GCC-Specific Check

If Copilot location was not available for DLP policies, label-based blocking through DLP may also be affected. However, sensitivity labels with encryption may independently restrict Copilot access:

> "In GCC, even if the DLP Copilot location isn't available yet, encrypted labels still restrict who can access the content — which limits what Copilot can process."

### Verification Steps

1. Open Copilot and ask: `"Summarize the Q4 revenue forecast"`
2. Copilot should refuse — file is labeled Highly Confidential > Restricted
3. Ask: `"What are Jane Doe's benefits?"`
4. Copilot should refuse — file is labeled Highly Confidential > Regulated Data
5. Ask about an unlabeled file — Copilot should respond normally

### Expert Callout

> "In GCC, Copilot DLP only supports label-based conditions. SIT-based conditions are not available for Copilot DLP rules in GCC. This lab uses a single policy with two label-based rules — one for Restricted content, one for Regulated Data."

---

## Phase 2 — Evidence & Investigations (Automated)

### GCC-Specific Check

Copilot audit events (`CopilotInteraction`) may not yet be available in GCC. If the pre-flight check returned no results or an error:

- Show DLP audit events (`DlpRuleMatch`) — these are available in GCC
- Explain that Copilot-specific audit events are rolling out to GCC
- Focus the demo on DLP policy match evidence

### Audit Trail

1. Navigate to **Microsoft Purview > Audit > Search**
2. Run the pre-configured searches:
   - `PVCopilotDLP-Copilot-Interaction-Audit` — Copilot interactions (if available)
   - `PVCopilotDLP-Copilot-DLP-Match-Audit` — DLP policy matches
   - `PVCopilotDLP-Copilot-Policy-Override-Audit` — override attempts
3. Show audit records with policy context

### eDiscovery Case

1. Navigate to **Microsoft Purview > eDiscovery > Cases**
2. Open `PVCopilotDLP-Copilot-DLP-Incident-Review`
3. Show the hold query and search results

### Key Message

> "Every time Copilot is constrained by DLP, there's a full audit trail. In GCC, this provides defensible AI governance with the controls currently available in your tenant."

---

## Pre-Demo Checklist (GCC)

- [ ] `Test-CopilotDlpReady.ps1 -Cloud gcc` returns a READY verdict
- [ ] DLP policies propagated (up to 4 hours after deploy; re-check after any mode switch)
- [ ] Sensitivity labels published to demo users
- [ ] Microsoft 365 Copilot for GCC licenses assigned to demo users
- [ ] Test documents uploaded to OneDrive and auto-labeled (check deploy log; fall back to portal labeling if Graph API unavailable in this GCC tenant)
- [ ] Auto-label policy has applied to any SSN-containing documents that missed Graph labeling
- [ ] Baseline demo completed (Phase 0) before policy enforcement
- [ ] Noted any GCC-unavailable features for "coming to GCC" callouts

---

## Optional: DSPM for AI (Commercial Reference)

DSPM for AI is Microsoft's posture-management surface for AI data security. Per Microsoft Learn, GCC availability is rolling out. For a GCC demo today:

1. **If DSPM for AI is available in your GCC tenant** — sign into the Microsoft Purview portal, navigate to **Solutions > DSPM for AI**, and follow the same activation flow as commercial (turn on audit, install browser extension, onboard devices, activate recommended one-click policies).
2. **If not yet available** — demo the DSPM for AI story against a commercial reference tenant and call out explicitly that the same experience is coming to GCC. The enforcement surface (this lab) is the stable part of the story; DSPM for AI is the posture surface that layers on top.

> **Demo framing (same as commercial):** "Enforcement + posture. This lab is enforcement — DLP stopping Copilot in the moment. DSPM for AI is posture — where oversharing still lives, which agencies still have CUI in over-shared SharePoint sites, where risk is accumulating."

---

## Switching from Simulation to Enforcement

DLP policies deploy in simulation mode by default. To enable enforcement for live demos:

1. Navigate to **Microsoft Purview > DLP > Policies**
2. Select each `PVCopilotDLP-*` policy
3. Change status from **Test it out** to **Turn it on**
4. Allow up to 4 hours for full propagation

Or redeploy without simulation mode by setting `"simulationMode": false` in the config.

> **Caution:** Switching a policy from simulation to enforced restarts the 4-hour propagation window. Rerun `./scripts/Test-CopilotDlpReady.ps1 -Cloud gcc` and wait for a READY verdict before presenting.
