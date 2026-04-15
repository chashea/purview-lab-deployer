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
