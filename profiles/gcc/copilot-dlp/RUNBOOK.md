# Copilot DLP Guardrails — Post-Deploy Runbook (GCC)

Complete these steps after running `Deploy-Lab.ps1` to prepare the full demo experience.

> **GCC Note:** Feature rollout for Copilot DLP may lag behind commercial. If any step references a feature not yet available in your GCC tenant, note it in the demo as "coming to GCC" and proceed with the remaining phases.

---

## Pre-Flight: Validate GCC Feature Availability

Before running the demo, confirm these features are active in your GCC tenant:

```powershell
# 1. Check CopilotLocation parameter
(Get-Command New-DlpCompliancePolicy).Parameters.Keys | Where-Object { $_ -like '*Copilot*' }

# 2. Check CopilotInteraction audit events
Search-UnifiedAuditLog -Operations CopilotInteraction -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -ResultSize 1

# 3. Verify sensitivity labels are published
Get-Label | Where-Object { $_.DisplayName -like 'PVCopilotDLP*' }
```

| Check | Expected | If Missing |
|---|---|---|
| CopilotLocation param | `CopilotLocation` in output | DLP policies skip Copilot location — add manually in portal when available |
| CopilotInteraction audit | Results or "no results" (not an error) | Copilot audit may not be enabled — Phase 4 audit demos will be limited |
| Published labels | PVCopilotDLP labels listed | Labels need time to publish — wait 15–30 minutes after deploy |

---

## Phase 0 — Baseline Demo (Manual, 5 min)

The baseline creates the before/after contrast. Show Copilot working without guardrails **before** DLP policies take effect.

> DLP policies deploy in simulation mode and may take 15–60 minutes to propagate. Use this window for the baseline demo.

### Steps

1. **Open Microsoft 365 Copilot** (copilot.microsoft.com or in-app)
2. **Ask Copilot to summarize a document** — use an unlabeled file on SharePoint
3. **Ask Copilot a question that references file content** — confirm it can reason over files
4. **Ask Copilot a general question** — confirm web-backed responses work

### Key Message

> "This is Copilot with no guardrails. It can summarize anything, search anything, and answer anything. Now let's put it inside the guardrails."

---

## Phase 1 — Verify DLP Prompt Blocking (Automated)

After policy propagation, verify the "Copilot Prompt SIT Block" policy is active.

### GCC-Specific Check

If the deployer warned that `CopilotLocation` was unavailable, the DLP policies were created without the Copilot scope. In that case:

1. Navigate to **Microsoft Purview > DLP > Policies**
2. Edit `PVCopilotDLP-Copilot Prompt SIT Block`
3. Add location: **Microsoft 365 Copilot** (if available in portal)
4. If not available in portal either, note this phase as "coming to GCC" and proceed to Phase 2

### Verification Steps (if Copilot location is active)

1. Confirm `PVCopilotDLP-Copilot Prompt SIT Block` shows status **TestWithNotifications**
2. Open Copilot and type a prompt containing a test SSN: `"Summarize the benefits for employee 078-05-1120"`
3. Copilot should display a policy-driven block message
4. Repeat with a credit card number: `"What charges were made on card 4532-8721-0034-6619?"`
5. Repeat with medical terms: `"Summarize the treatment plan for diabetes mellitus"`

### Expected Behavior

| Prompt Contains | Copilot Response |
|---|---|
| SSN (078-05-1120) | Blocked — policy message shown |
| Credit card (4532-8721-...) | Blocked — policy message shown |
| Medical terms (diabetes mellitus) | Blocked — policy message shown |
| No sensitive data | Normal response |

---

## Phase 2 — Verify Label-Based Blocking (Automated)

### Pre-Demo File Labeling

The auto-label policy catches SSN content automatically. For the demo, also manually label test files:

1. Navigate to **SharePoint > Lab document library**
2. Apply label **Highly Confidential > Restricted** to `Q4-Revenue-Forecast.txt`
3. Apply label **Highly Confidential > Regulated Data** to `Employee-Benefits-Summary.txt` (may auto-label via SSN detection)
4. Leave `Patient-Intake-Notes.txt` unlabeled initially (for before/after contrast)

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

> "SIT + label conditions cannot be combined in the same DLP rule. We use separate policies — one for prompt content (SIT-based), one for file labels (label-based). You can have multiple rules in one policy, but each rule uses one condition type."

---

## Phase 3 — Web Search Prevention (Private Preview)

> **GCC Status:** This feature is in Private Preview for commercial tenants. GCC availability is TBD. If not available, walk through the policy logic and explain the control.

### If Available

1. Navigate to **Microsoft Purview > DLP > Policies**
2. Create a new policy for Copilot web search location
3. Test with a prompt that triggers web search with sensitive context

### If Not Available

Walk through the policy logic on screen and explain:

> "Even if Copilot could answer the question by searching the web, Purview decides it shouldn't — because the prompt contains sensitive data that would leave the compliance boundary. This capability is rolling out to GCC."

---

## Phase 4 — Evidence & Investigations (Automated)

### GCC-Specific Check

Copilot audit events (`CopilotInteraction`) may not yet be available in GCC. If the pre-flight check returned no results or an error:

- Show DLP audit events (`DlpRuleMatch`) — these are available in GCC
- Explain that Copilot-specific audit events are "coming to GCC"
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

> "Every time Copilot is constrained by DLP, there's a full audit trail. This works the same in GCC as commercial — defensible AI governance for government workloads."

---

## Pre-Demo Checklist (GCC)

- [ ] Pre-flight validation passed (CopilotLocation, audit events, labels)
- [ ] DLP policies propagated (15–60 min after deploy)
- [ ] Sensitivity labels published to demo users
- [ ] Copilot licenses assigned to test users (mtorres, jkim) — GCC Copilot availability confirmed
- [ ] Test documents uploaded to SharePoint
- [ ] At least one document manually labeled Highly Confidential > Restricted
- [ ] Auto-label policy has applied to SSN-containing documents
- [ ] Baseline demo completed (Phase 0) before policy enforcement
- [ ] Noted any GCC-unavailable features for "coming to GCC" callouts

---

## Switching from Simulation to Enforcement

DLP policies deploy in simulation mode by default. To enable enforcement for live demos:

1. Navigate to **Microsoft Purview > DLP > Policies**
2. Select each `PVCopilotDLP-*` policy
3. Change status from **Test it out** to **Turn it on**
4. Allow 15–30 minutes for propagation

Or redeploy without simulation mode by setting `"simulationMode": false` in the config.
