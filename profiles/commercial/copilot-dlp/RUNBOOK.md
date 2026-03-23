# Copilot DLP Guardrails — Post-Deploy Runbook

Complete these steps after running `Deploy-Lab.ps1` to prepare the full demo experience.

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

### Verification Steps

1. Navigate to **Microsoft Purview > Data loss prevention > Policies**
2. Confirm `PVCopilotDLP-Copilot Prompt SIT Block` shows status **TestWithNotifications** (or **Enable** if switched)
3. Open Copilot and type a prompt containing a test SSN: `"Summarize the benefits for employee 078-05-1120"`
4. Copilot should display a policy-driven block message
5. Repeat with a credit card number: `"What charges were made on card 4532-8721-0034-6619?"`
6. Repeat with medical terms: `"Summarize the treatment plan for diabetes mellitus"`

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

### Verification Steps

1. Open Copilot and ask: `"Summarize the Q4 revenue forecast"`
2. Copilot should refuse — file is labeled Highly Confidential > Restricted
3. Ask: `"What are Jane Doe's benefits?"`
4. Copilot should refuse — file is labeled Highly Confidential > Regulated Data
5. Ask about an unlabeled file — Copilot should respond normally
6. Now label `Patient-Intake-Notes.txt` as Highly Confidential > Restricted
7. Ask Copilot about it again — now blocked

### Expected Behavior

| File Label | Copilot Response |
|---|---|
| Highly Confidential > Restricted | Blocked — cannot summarize or reference |
| Highly Confidential > Regulated Data | Blocked — cannot summarize or reference |
| Confidential > General | Allowed — normal processing |
| No label | Allowed — normal processing |

### Expert Callout

> "Notice that SIT + label conditions cannot be combined in the same DLP rule. We use separate policies — one for prompt content (SIT-based), one for file labels (label-based). You can have multiple rules in one policy, but each rule uses one condition type."

---

## Phase 3 — Web Search Prevention (Private Preview)

This capability prevents Copilot from using sensitive data for external web search queries. It is currently in **Private Preview**.

### If Preview-Enrolled

1. Navigate to **Microsoft Purview > DLP > Policies**
2. Create a new policy manually:
   - Location: **Microsoft 365 Copilot (web search)**
   - Condition: Content contains sensitive info types (SSN, Credit Card)
   - Action: Block
3. Test by asking Copilot a question that would trigger web search with sensitive context
4. Copilot should be prevented from sending sensitive data to web search

### If Not Preview-Enrolled

Walk through the policy logic on screen (portal UI) and explain:

> "Even if Copilot could answer the question by searching the web, Purview decides it shouldn't — because the prompt contains sensitive data that would leave the compliance boundary."

### References

- [Purview DLP for Copilot web search](https://learn.microsoft.com/purview/dlp-microsoft-copilot#web-search)

---

## Phase 4 — Evidence & Investigations (Automated)

### Audit Trail

1. Navigate to **Microsoft Purview > Audit > Search**
2. Run the pre-configured searches:
   - `PVCopilotDLP-Copilot-Interaction-Audit` — all Copilot interactions
   - `PVCopilotDLP-Copilot-DLP-Match-Audit` — DLP policy matches
   - `PVCopilotDLP-Copilot-Policy-Override-Audit` — override attempts
3. Show audit records:
   - Prompt blocked (DlpRuleMatch)
   - File excluded from Copilot (DlpRuleMatch with label context)
   - Policy responsible (policy name in record)

### eDiscovery Case

1. Navigate to **Microsoft Purview > eDiscovery > Cases**
2. Open `PVCopilotDLP-Copilot-DLP-Incident-Review`
3. Show the hold query preserving Copilot-related communications
4. Run the search query to find sensitive data references

### Key Message

> "Every time Copilot is constrained by DLP, there's a full audit trail. Security teams can see exactly which prompt was blocked, which file was excluded, and which policy was responsible. This is defensible AI governance."

---

## Pre-Demo Checklist

- [ ] DLP policies propagated (15–60 min after deploy)
- [ ] Sensitivity labels published to demo users
- [ ] Copilot licenses assigned to test users (mtorres, jkim)
- [ ] Test documents uploaded to SharePoint
- [ ] At least one document manually labeled Highly Confidential > Restricted
- [ ] Auto-label policy has applied to SSN-containing documents
- [ ] Baseline demo completed (Phase 0) before policy enforcement
- [ ] Audit logging enabled and searches returning results

---

## Switching from Simulation to Enforcement

DLP policies deploy in simulation mode by default. To enable enforcement for live demos:

1. Navigate to **Microsoft Purview > DLP > Policies**
2. Select each `PVCopilotDLP-*` policy
3. Change status from **Test it out** to **Turn it on**
4. Allow 15–30 minutes for propagation

Or redeploy without simulation mode by setting `"simulationMode": false` in the config.
