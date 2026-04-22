# Copilot DLP Guardrails — Post-Deploy Runbook

Complete these steps after running `Deploy-Lab.ps1` to prepare the full demo experience.

---

## Pre-Flight Checks (Commercial)

Run the automated readiness check — it verifies policies, labels, label publishing, and Copilot licenses in one pass:

```powershell
./scripts/Test-CopilotDlpReady.ps1 -LabProfile copilot-protection -Cloud commercial
```

The script reports a `READY / WAIT / BLOCKED` verdict per check and prints an ETA when policies are still inside the 4-hour propagation window. Green across the board = safe to present.

Manual spot-checks (only if the script flags something):

1. Policy location is correctly set to Microsoft 365 Copilot and Copilot Chat:
   ```powershell
   Get-DlpCompliancePolicy -Identity 'PVCopilotDLP-Copilot Prompt SIT Block' | Select-Object Name, Mode, EnforcementPlanes, Locations
   ```
2. Sensitivity labels exist:
   ```powershell
   Get-Label | Where-Object { $_.DisplayName -like 'PVCopilotDLP*' }
   ```

> DLP policy changes can take up to 4 hours to fully appear in Copilot and Copilot Chat experiences.

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

## Phase 1 — Verify DLP Prompt Blocking (Automated, Public Preview)

After policy propagation, verify the "Copilot Prompt SIT Block" policy is active. This control is in **public preview** per Microsoft Learn — rollout reaches tenants on a schedule, so confirm availability before the demo.

### Verification Steps

1. Navigate to **Microsoft Purview > Data loss prevention > Policies**
2. Confirm `PVCopilotDLP-Copilot Prompt SIT Block` shows status **TestWithNotifications** (or **Enable** if switched)
3. Open Copilot and type a prompt containing a test SSN: `"Summarize the benefits for employee 078-05-1120"`
4. Copilot should display a policy-driven block message
5. Repeat with a credit card number: `"What charges were made on card 4532-8721-0034-6619?"`
6. Repeat with medical terms: `"Summarize the treatment plan for diabetes mellitus"`

> Prompt SIT blocking evaluates text typed directly in prompts. Uploaded file contents in prompts are not DLP-scanned. The same policy also prevents the sensitive prompt text from being used for internal or external web searches — no separate web-search policy is required.

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

Documents are uploaded to the owner's OneDrive and labeled automatically during deployment via the Microsoft Graph `assignSensitivityLabel` API. The SSN auto-label policy also catches sensitive content.

| File | Owner | Label applied at deploy |
|---|---|---|
| `Q4-Revenue-Forecast.txt` | rtorres | Highly Confidential > Restricted |
| `Employee-Benefits-Summary.txt` | rtorres | Highly Confidential > Regulated Data (redundant with auto-label) |
| `Patient-Intake-Notes.txt` | mchen | Unlabeled (for before/after contrast) |

If the Graph call fails (e.g., tenant hasn't enabled sensitivity labels for Office files in SharePoint/OneDrive, or the signed-in principal lacks `Files.ReadWrite.All`), the deployer logs a warning and you can apply the labels manually in the OneDrive web UI.

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

## Phase 3 — Evidence & Investigations (Automated)

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

- [ ] `Test-CopilotDlpReady.ps1` returns a READY verdict (green across the board)
- [ ] DLP policies propagated (up to 4 hours after deploy; re-check after any mode switch)
- [ ] Sensitivity labels published to demo users
- [ ] Microsoft 365 Copilot licenses assigned to demo users (rtorres, mchen)
- [ ] Test documents uploaded to OneDrive and auto-labeled (check deploy log for `assignSensitivityLabel` successes)
- [ ] Auto-label policy has applied to any SSN-containing documents that missed Graph labeling
- [ ] Baseline demo completed (Phase 0) before policy enforcement
- [ ] Audit logging enabled and searches returning results

---

## Optional: Activate DSPM for AI

Data Security Posture Management for AI (DSPM for AI) layers on top of this lab and is the Microsoft-recommended "front door" for AI data security. It's optional for the demo, but strong natural follow-up.

1. Sign into **[Microsoft Purview portal](https://purview.microsoft.com/)** as a user in the **Compliance Administrator** role (or equivalent).
2. Go to **Solutions > DSPM for AI**.
3. From **Overview**, review the **Get started** section and complete the prerequisites that aren't already green (audit is auto-on for new tenants; browser extension and device onboarding are required for third-party AI site visibility).
4. Under **Recommendations**, activate the one-click policies that match your demo story:
   - **Protect your data with sensitivity labels** — creates a default label taxonomy if you don't already have one.
   - **Extend your insights for data discovery** — turns on the third-party AI site collection policies (Gemini, ChatGPT, etc.).
   - **Detect risky AI usage** — creates Insider Risk policies focused on AI activity.
5. After 24 hours, return to DSPM for AI > **Reports** to see **Sensitive interactions per generative AI app**, AI activity volume, and the default weekly data risk assessment for the top 100 SharePoint sites.

> **Demo framing:** "This lab shows the enforcement surface — DLP stopping Copilot in the moment. DSPM for AI shows the posture surface — where oversharing still lives, which users take the most AI risk, and which SharePoint sites need labeling before Copilot touches them. Enforcement + posture is the complete story."

> **GCC note:** DSPM for AI is available on commercial today. GCC availability is rolling out — validate in your tenant before referencing in a government demo.

---

## Switching from Simulation to Enforcement

DLP policies deploy in simulation mode by default. To enable enforcement for live demos:

1. Navigate to **Microsoft Purview > DLP > Policies**
2. Select each `PVCopilotDLP-*` policy
3. Change status from **Test it out** to **Turn it on**
4. Allow up to 4 hours for full propagation

Or redeploy without simulation mode by setting `"simulationMode": false` in the config.

> **Caution:** Switching a policy from simulation to enforced restarts the 4-hour propagation window. Rerun `./scripts/Test-CopilotDlpReady.ps1` and wait for a READY verdict before presenting.
