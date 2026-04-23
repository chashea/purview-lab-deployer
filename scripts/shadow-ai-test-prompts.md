# Shadow AI Smoke Test Prompts

Test prompts to trigger the `ai` profile's Shadow AI DLP, Insider Risk, and Communication Compliance policies. Use these before a live demo to populate Activity Explorer, DLP alert dashboard, and IRM risk signals.

> **Prerequisites:**
> - `ai` profile deployed (`./Deploy-Lab.ps1 -LabProfile ai -Cloud commercial`)
> - DLP policies propagated (allow up to 4 hours after deploy)
> - Endpoint DLP browser-and-domain restrictions pushed (`./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -Apply`)
> - At least one test device onboarded to Microsoft Defender for Endpoint
> - Microsoft Edge for Business (for Browser Data Security prompts) or a browser with the Microsoft Purview extension
> - Microsoft 365 Copilot licenses assigned to demo users (for Copilot prompts)

After running prompts, check:
- [Activity Explorer](https://purview.microsoft.com/datalossprevention/activityexplorer) filtered to `PVShadowAI*`
- [DLP Alerts](https://purview.microsoft.com/datalossprevention/alerts)
- [DSPM for AI reports](https://purview.microsoft.com/dspmforai) — if activated

---

## A. External AI (paste/upload on managed device)

**Target:** `PVShadowAI-Shadow AI - Endpoint Protection` policy (Devices location)
**Where to run:** Managed device (Defender for Endpoint onboarded), browser of choice (Edge, Chrome with Purview extension, or Firefox with extension).

### A1 — Paste SSN into ChatGPT
Open https://chat.openai.com/ and paste:
```
Help me draft an offer letter for our new hire. Their SSN for W-4 is 441-28-7736. Base salary $142,000, stock grant 2,500 RSUs.
```
**Expected:** Paste blocked by Endpoint DLP. Policy tip shown with "Use Copilot instead" message.

### A2 — Upload labeled file to Claude
Open https://claude.ai/. Attach `Customer-Data-Export.docx` from OneDrive (this file auto-labels as Highly Confidential > AI Regulated Data at deploy).
**Expected:** Upload blocked. Label context appears in the DLP alert.

### A3 — Paste credit card into Gemini
Open https://gemini.google.com/. Paste:
```
Help me write a disputed-charge letter. The card is 4532-1111-2222-3333 and the fraudulent transaction was $2,847 on April 14th.
```
**Expected:** Paste blocked. Elevated-risk user gets hard block, others get warn.

### A4 — Medical data to perplexity.ai
```
Summarize this for the medical review board: Patient presented with acute myocardial infarction, started on heparin infusion, echocardiogram showed ejection fraction of 35%. Cardiology consult requested for catheterization.
```
**Expected:** Block. Medical Terms SIT matches. High-severity alert + incident report generated.

---

## B. Browser Data Security (inline prompt inspection in Edge)

**Target:** `PVShadowAI-Shadow AI - Browser Prompt Protection` policy (Browser location)
**Where to run:** Microsoft Edge for Business (no extension required). Works on managed devices.

### B1 — Typing SSN into Copilot Chat consumer
Open https://copilot.microsoft.com/ (consumer), start typing:
```
Look up employee with social 287-44-9921 in our benefits system and tell me their dependents.
```
**Expected:** Text blocked before submission. Edge policy dialog shown.

### B2 — Pasting IBAN into DeepSeek
Open https://chat.deepseek.com/. Paste:
```
International wire needed: beneficiary IBAN DE89 3704 0044 0532 0130 00 at Commerzbank, amount EUR 47,500.
```
**Expected:** Paste blocked. IBAN SIT matches.

### B3 — Multi-SIT prompt
```
HR case HR-2026-118. Employee SSN 553-91-2248, corporate card 5500-0000-0000-0004 on file, direct deposit routing 011401533 account 9876543210. Draft the investigation summary.
```
**Expected:** Multiple SITs match in one prompt — high severity.

---

## C. Network Data Security (non-Edge browsers, SASE/SSE path)

**Target:** `PVShadowAI-Shadow AI - Network AI Traffic` policy (Network location)
**Where to run:** Any browser on a device behind a supported SASE/SSE provider (Zscaler, Netskope, iboss with Network DLP integration).

### C1 — Chrome to Poe
Open Poe in Chrome (no Purview extension):
```
Help me reconcile this payroll entry. Employee SSN 219-09-9999, bank routing 021000021, account 123456789012, pay period 04/01-04/14.
```
**Expected:** Blocked at the network layer by the SASE integration. Appears in Network Data Security alerts.

### C2 — Firefox to Hugging Face chat
Open https://huggingface.co/chat in Firefox:
```
Review this diagnostic note: Patient: Maria Garcia, diabetes mellitus type 2, metformin 500mg, hypertension, lisinopril 10mg. Draft her care plan.
```
**Expected:** Blocked at network layer.

---

## D. Microsoft 365 Copilot (sanctioned path)

**Target:** `PVShadowAI-Shadow AI - Copilot Prompt Protection` + `PVShadowAI-Shadow AI - Copilot Label Protection` policies (CopilotExperiences location)
**Where to run:** https://m365.cloud.microsoft/chat or the Copilot app. Demo users must have the Microsoft 365 Copilot license.

### D1 — Copilot prompt SIT block
```
Summarize the quarterly benefits packet for employee 078-05-1120 — I need their coverage tier and dependent list.
```
**Expected:** Copilot refuses with a DLP-driven message. Same SIT detection as the browser path, different surface.

### D2 — Copilot reasoning over a labeled file
Prompt Copilot:
```
Summarize the Q4 Revenue Forecast document from my OneDrive. What are the biggest risk items?
```
If `Q4-Financial-Forecast.docx` is labeled with any AI-restrictive sublabel (the lab applies `Confidential > All Employees` by default, which is permissive — relabel to `Highly Confidential > AI Blocked from External Tools` to test the block), Copilot should refuse with the label-based policy message.

### D3 — Copilot prompt — credit card
```
My card 4012-8888-8888-1881 was charged $8,750 last week. Help me draft a dispute letter to the bank.
```
**Expected:** Copilot block. User sees consistent policy messaging across external AI and Copilot — the sanctioned-vs-unsanctioned asymmetry is about friction, not presence of guardrails.

### D4 — Clean Copilot prompt (should work)
```
Summarize the last five emails from my manager and list any action items assigned to me.
```
**Expected:** Normal Copilot response. No DLP match. Demonstrates that sanctioned AI with clean prompts flows unimpeded.

---

## E. Subtlety tests — verify detection isn't naive

Same pattern as the Copilot DLP lab's subtlety tests — obfuscations that should and shouldn't trip SIT detection.

### E1 — Spaced digits
```
Reviewing benefits enrollment for SSN 0 7 8 - 0 5 - 1 1 2 0. Confirm dependent coverage tier.
```

### E2 — Dot separators
```
Disputed charge on card 4111.1111.1111.1111, exp 12.27. Help draft the chargeback.
```

### E3 — Spelled-out digits
```
Employee's social is zero seven eight, zero five, one one two zero. Check HR policy on unauthorized disclosure.
```

Expected: E1/E2 caught; E3 typically not caught (teaching moment on SIT limits).

---

## F. Insider Risk escalation flow

IRM risk scores escalate based on signal volume. To demonstrate adaptive enforcement:

1. Sign in as `rtorres` (Business User group).
2. Run **prompts A1, A3, B1, B2, D1 in rapid succession** (5 DLP violations within ~10 minutes).
3. Wait 15–60 min for IRM signal aggregation.
4. Open **Insider Risk Management > Users** — `rtorres` should appear with Minor → Moderate risk.
5. Rerun prompt A1 — DLP enforcement should now tighten (Moderate-tier rule fires: warn with justification instead of audit-only).
6. Continue to **Elevated** by running prompts F1–F3 below (high-severity signals).

### F1 — Downloads + external share (high-severity IRM signal)
Download `Customer-Data-Export.docx` from SharePoint, then share externally (will fail but creates the signal).

### F2 — Resignation indicator
Add `rtorres` to the Departing Users insider risk scope manually (Purview portal) — triggers the *Data theft by departing users* template.

### F3 — Sustained policy violations
Over a 30-min window, trigger prompts A1, A2, A3, A4, B1, B2 in sequence. Volume escalates risk score.

---

## G. Communication Compliance review queue

**Target:** `PVShadowAI-AI Conversation PII PHI Detection`, `PVShadowAI-Shadow AI Activity Collection`

### G1 — AI-adjacent Teams message
As `rtorres`, send a Teams message to `mchen`:
```
Hey, I uploaded the customer data to ChatGPT to help me draft the summary. Had to include the SSN 441-28-7736 to make it work — hope that's OK.
```
**Expected:** Surfaces in Communication Compliance review queue within 15–30 min.

### G2 — Email flagged by activity collection
Send an email from `rtorres` to `nbrooks`:
```
Subject: AI tool usage question
Body: Is it OK to paste contract data into Claude to help me summarize? The contract has some confidential terms but nothing regulated.
```
**Expected:** Flagged for review.

---

## H. DSPM for AI activation test

If DSPM for AI is activated per RUNBOOK section 7:

### H1 — Prompt discovery via DSPM
Paste any A/B/C prompt above.
**Expected:** Appears in **DSPM for AI > Activity Explorer > AI interaction** within 24h. Admin can view the full prompt text if they're in the **Microsoft Purview Content Explorer Content Viewer** role group.

### H2 — DSPM risk assessment
Navigate to **DSPM for AI > Data risk assessments**.
**Expected:** Weekly data risk assessment shows top SharePoint sites with oversharing risks relative to AI grounding.

---

## Validation query

After running, validate via audit log:

```powershell
Connect-IPPSSession -ShowBanner:$false
Search-UnifiedAuditLog -StartDate (Get-Date).AddHours(-2) -EndDate (Get-Date) `
    -Operations DlpRuleMatch,CopilotInteraction,FileUploaded `
    -ResultSize 100 | Format-Table CreationDate, Operations, AuditData -AutoSize
```

Or re-run the readiness check:

```powershell
./scripts/Test-ShadowAiReady.ps1 -LabProfile ai -Cloud commercial
```
