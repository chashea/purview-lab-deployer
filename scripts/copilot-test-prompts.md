# Copilot DLP Smoke Test Prompts

Test prompts to paste into **Microsoft 365 Copilot** (copilot.microsoft.com, Teams Copilot Chat, or in-app Copilot) to trigger DLP policy matches and generate alerts in Purview.

> **Prerequisite:** DLP policies must be deployed and propagated (up to 4 hours after deploy).
> After pasting each prompt, check for alerts at https://purview.microsoft.com/datalossprevention/alerts

---

## SSN Detection

**Target rule:** PVLab-Detect Social Security Numbers / PVCopilotDLP-Block SSN in Copilot Prompts

### Prompt 1 — Employee Lookup
```
Can you help me draft an email to HR about updating the direct deposit for employee Rachel Torres?
Her SSN is 078-05-1120 and she needs her tax withholding corrected for the W-2 filing.
```

### Prompt 2 — Background Check
```
Summarize the background check results for our new hire. The applicant's Social Security Number
is 219-09-9999 and their start date is May 1st. What onboarding steps should I prioritize?
```

### Prompt 3 — Payroll Issue
```
I need to investigate a payroll discrepancy. The employee's SSN on file is 123-45-6789 but their
W-4 shows 987-65-4321. Can you help me draft a memo to payroll about the correction?
```

---

## Credit Card Detection

**Target rule:** PVLab-Detect Credit Card Numbers / PVCopilotDLP-Block Credit Card in Copilot Prompts

### Prompt 4 — Invoice Payment
```
Draft a reply to the vendor about their overdue invoice. The client authorized payment with credit
card 4111-1111-1111-1111, expiration 12/27, CVV 123. What's the standard language for
confirming a card payment?
```

### Prompt 5 — Expense Report
```
Can you format this expense report entry? Employee used corporate Visa 5500-0000-0000-0004
for a $2,400 conference registration at the Gartner IT Symposium. Receipt attached.
```

### Prompt 6 — Fraud Investigation
```
We're reviewing a suspicious charge on card number 4012-8888-8888-1881 for $8,750. The
transaction was flagged by our fraud detection system. Help me draft the chargeback dispute letter.
```

---

## Bank Account Detection

**Target rule:** PVLab-Detect Bank Account Numbers

### Prompt 7 — Wire Transfer
```
Help me set up a wire transfer to our new vendor. Their banking details are: ABA routing number
021000021, checking account 123456789012, Bank of America. The payment amount is $47,500
for Q4 consulting services.
```

### Prompt 8 — Direct Deposit
```
An employee submitted new direct deposit information: routing number 011401533, account number
9876543210 at Chase Bank. Can you draft the confirmation email for HR?
```

---

## Medical / PHI Detection

**Target rule:** PVLab-Detect Medical Terms / PVCopilotDLP-Block PHI in Copilot Prompts

### Prompt 9 — Accommodation Request
```
Help me respond to an employee accommodation request. They were diagnosed with major depressive
disorder and generalized anxiety disorder per DSM-5. Their psychiatrist recommends a modified
work schedule and ergonomic workstation assessment. What are our ADA obligations?
```

### Prompt 10 — Workplace Injury
```
Summarize this workplace injury report for the safety committee: Employee sustained a lumbar disc
herniation at L4-L5 confirmed by MRI. Radiculopathy with nerve impingement noted. They've been
referred to orthopedic surgery. What OSHA reporting requirements apply?
```

### Prompt 11 — Health Records
```
Review this occupational health summary: Patient presented with acute myocardial infarction, started
on aspirin, clopidogrel, and heparin infusion. Echocardiogram showed ejection fraction of 35%.
Cardiology consult requested for cardiac catheterization. Draft a return-to-work plan.
```

---

## Multi-SIT Prompts (trigger multiple rules at once)

### Prompt 12 — HR Case File
```
I'm preparing an HR investigation packet. The employee's SSN is 078-05-1120, their corporate card
4111-1111-1111-1111 was used for unauthorized purchases, and their direct deposit goes to routing
021000021 account 123456789012. Help me organize this into a case summary.
```

### Prompt 13 — Complete Employee Record
```
Draft a confidential employee profile summary for legal review:
- Name: Marcus Chen
- SSN: 219-09-9999
- Corporate Card: 5500-0000-0000-0004
- Bank: routing 011401533, account 9876543210
- Medical: diagnosed with generalized anxiety disorder, on FMLA leave
What sections should I include in the legal hold notice?
```

---

## Subtlety tests — verify detection isn't naive

Purview SITs use pattern matching with checksums and proximity rules. These prompts test whether the detector catches common obfuscations or falls through. If any of these are NOT caught, tune the SIT confidence threshold.

### Prompt S1 — Spaced digits
```
Look up the benefits enrollment for employee with social security 0 7 8 - 0 5 - 1 1 2 0 and
confirm whether their dependents are covered on the family plan this year.
```

### Prompt S2 — Dot separators
```
Please cross-reference this account for the year-end audit: card number 4111.1111.1111.1111
expiring 12.27 — was it active during the December billing cycle?
```

### Prompt S3 — Bracketed SSN
```
Archive this personnel record: Jane Doe [SSN: 078-05-1120] — her file needs to move to the
long-term retention repository per our records schedule.
```

### Prompt S4 — Natural-language embedding
```
I need help drafting a warning letter. The employee's social is zero seven eight, zero five,
one one two zero. Can you explain what our policy says about unauthorized disclosure?
```

### Prompt S5 — Trailing noise
```
Employee record for payroll correction --- SSN078051120 --- please validate this against the
W-4 we have on file and escalate if it doesn't match.
```

Expected: S1, S2, S3 should be caught by standard SIT detection (format-agnostic patterns). S4 (spelled-out digits) typically is NOT caught — useful teaching moment. S5 (no separators) depends on SIT configuration.

---

## Label-based prompts — target files, not prompt text

These prompts reference files that should be labeled Highly Confidential in the demo tenant. They test the **Copilot Labeled Content Block** policy (Phase 2), not the prompt SIT policy.

### Prompt L1 — Summarize labeled file
```
Summarize the Q4 Revenue Forecast for me. What are the projected Q4 numbers and the biggest risks?
```

### Prompt L2 — Reason over labeled file
```
Compare the employee benefits summary with the standard benefits plan. What's the delta in coverage
for dependents?
```

### Prompt L3 — Cross-file reasoning
```
Based on the documents in my OneDrive, what are the top three compliance risks I should raise with
the audit committee next week?
```

Expected: All three should receive a blocked / redacted response citing the sensitivity label, because the files `Q4-Revenue-Forecast.txt` and `Employee-Benefits-Summary.txt` are labeled Highly Confidential and auto-blocked from Copilot processing.

---

## Clean control prompts — should NOT trigger any DLP

Use these in Phase 0 (baseline) to prove Copilot works normally before guardrails engage.

### Prompt C1
```
What are the key meetings I have this week, and can you draft agenda talking points for each one?
```

### Prompt C2
```
Summarize the last five emails from my manager. What decisions is she asking me to weigh in on?
```

### Prompt C3
```
Help me write a proposal for adopting Microsoft 365 Copilot across our legal team. Focus on time
savings for contract review and discovery workflows.
```

Expected: Clean responses, no DLP blocks. If any of these trigger a block, your SIT rules are over-tuned.

---

## Validation

After running prompts, validate DLP matches:

```powershell
# Connect and query audit log
Connect-IPPSSession -ShowBanner:$false
Search-UnifiedAuditLog -StartDate (Get-Date).AddHours(-2) -EndDate (Get-Date) -Operations DlpRuleMatch -ResultSize 50 | Format-Table CreationDate, Operations, AuditData -AutoSize
```

Or use the smoke test script in validate mode:

```powershell
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic-lab -ValidateOnly -Since (Get-Date).AddHours(-2)
```
