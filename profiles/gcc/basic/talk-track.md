# Basic Purview Lab — GCC Customer Talk Track

## Overview

**Duration:** 25–35 minutes (expandable to 60 with hands-on)
**Audience:** Federal/SLG CISO, Compliance leadership, IT decision-makers evaluating Microsoft Purview on a GCC tenant
**Goal:** Show the core Purview compliance stack end-to-end — labels, DLP, retention, eDiscovery, communication compliance, insider risk, conditional access, and audit — running on a Microsoft 365 G5 (GCC) tenant. No AI-specific scenarios; this is the foundation everything else builds on.

**Exec tagline:** "This is what Purview looks like when it's doing its job in GCC — classifying, protecting, retaining, investigating, and auditing your data, with a single policy surface and a single audit trail. Same platform you'd see in commercial, with the GCC-specific feature deltas called out as we go."

---

## Opening (2 min)

> "Every compliance conversation eventually lands on the same five questions:
> 1. Do we know what data we have?
> 2. Is it labeled and protected?
> 3. Can we stop it from leaving?
> 4. Can we keep what we need to keep, and delete what we need to delete?
> 5. If something goes wrong, can we find out who did what, and build a case?
>
> That's the whole Purview story. This lab deploys a working version of each piece on the same GCC tenant — one config, one command, removable. Let's walk through it."

---

## The demo personas (2 min)

**Show:** Entra ID → Users filtered to the eight pre-existing demo accounts (no users are created by the deployer in GCC; we target accounts that already exist in `MngEnvMCAP659995.onmicrosoft.com`).

| User | Persona | Group memberships |
|---|---|---|
| mtorres | HR Director | Legal-Team |
| mahmed | Finance Analyst | Finance-Team |
| nshah | General Counsel | Legal-Team |
| opark | Risky/departing employee | — |
| DebraB | Sales executive | Executives |
| NestorW | CFO | Executives, Finance-Team |
| JoniS | Line employee | — |
| jkim | HR / Compliance liaison | Legal-Team |

**Groups:** `PVLab-Executives`, `PVLab-Finance-Team`, `PVLab-Legal-Team` — the basic scoping model every Purview workload inherits.

> "Eight users, three groups. Enough variety to show group-based scoping without getting lost in a huge directory. In GCC the lab targets pre-existing tenant accounts so we don't churn licenses on every deploy."

---

## Act 1: Sensitivity Labels — "Classify once, protect everywhere" (5 min)

**Portal:** Purview → Information Protection → Labels

**Show the taxonomy:**

| Parent | Sublabels | Use case |
|---|---|---|
| Confidential | Medical, Financial, HR, All-Employees, Recipients Only | Everyday sensitive business content, encrypted by category |
| Highly Confidential | Medical, Financial, HR, All-Employees, Recipients Only | Restricted content with the same five facets, escalated |

> "Two parent labels, ten sublabels. Each sublabel carries its own encryption, header/footer markings, and access rules — picked by category (Medical, Financial, HR) rather than by audience. Users pick the label, the platform does the enforcement."

**Show the two auto-label policies:**

- SSN auto-apply → `Confidential\Recipients Only`
- US EIN / IBAN / SWIFT Code auto-apply → `Confidential\All-Employees`

> "Users don't need to remember to label. When a document or email contains an SSN, Purview applies the Recipients-Only label automatically. International banking identifiers escalate to the All-Employees variant. Both are deployed and active out of the box."

**Demo sublabel naming convention:** `PVLab-<Parent>-<Sublabel>` with spaces replaced by hyphens. Example identities the lab uses on uploaded documents:

- `PVLab-Highly-Confidential-Financial`
- `PVLab-Confidential-Medical`
- `PVLab-Highly-Confidential-Recipients-Only`

---

## Act 2: DLP — "Four policies covering the regulated-data footprint" (5 min)

**Portal:** Purview → Data Loss Prevention → Policies

**Show the 4 policies:**

| Policy | Locations | What it catches |
|---|---|---|
| US PII Protection | Exchange, SharePoint, OneDrive | SSN or Credit Card (min 1) → block + alert |
| Financial Data Protection | Exchange, SharePoint, OneDrive, Teams | US Bank Account or Credit Card (min 1) → block + alert |
| HR Case Data Protection | Exchange, SharePoint, OneDrive | SSN or Bank Account (min 1) → block + alert |
| Workplace Health Record Protection | Exchange, SharePoint, OneDrive, Teams | Medical terms or SSN (min 1) → block + alert |

> "Four policies, low thresholds — every match matters in a regulated workload. SSN, credit card, bank account, and medical terms are all built-in Microsoft sensitive info types, so there's no SIT authoring to do. Same SIT (Social Security Number), scoped differently to the workloads where each business unit works."

**Show what a DLP hit looks like:**

- Policy tip in Outlook ("This message contains sensitive info and can't be sent to external recipients")
- Policy tip in Word/Excel when opening a file
- Alert in Purview → DLP → Alerts

> "The user sees the policy tip before they hit send. The compliance team sees the alert after. Same event, two audiences. The post-deploy smoke test sends ten emails and uploads six documents that exercise every one of these policies."

---

## Act 3: Retention — "Keep what you need, delete what you don't" (3 min)

**Portal:** Purview → Data Lifecycle Management → Retention Policies

**Show the 2 policies:**

| Policy | Action | Duration | Locations |
|---|---|---|---|
| `PVLab-Financial Records Retention` | retain + delete | 2555 days (7 years) | Exchange, SharePoint |
| `PVLab-Legal Hold Policy` | retain only | 365 days (1 year) | Exchange, OneDrive |

> "Two time horizons for two regulatory regimes. Financial records live 7 years because SOX says so. Legal-team holds are 1 year, retain-only — nothing is auto-deleted. Both policies are automatic — no user decisions, no forgotten retention tags."

---

## Act 4: eDiscovery — "From alert to legal production" (5 min)

**Portal:** Purview → eDiscovery → Cases → `PVLab-Data-Breach-Investigation`

**Show the case structure:**

- **Custodians:** mahmed, NestorW, jkim, JoniS — pre-attached, mailboxes and OneDrive sites on hold
- **Hold query:** `subject:"confidential" OR subject:"classified" OR body:"breach" OR body:"unauthorized"` (with a `received>=2024-01-01` floor)
- **Searches → Review sets** (pre-built):
  - `Financial-Records` (wire transfer / account number) → `Financial-Review`
  - `PII-Exfil` (social security / SSN / credit card) → `PII-Review`
  - `Suspicious-Activity` (unauthorized access / breach) → `Incident-Review`

**Then show the second case:** `PVLab-HR-Investigation` — workplace conduct scenario with custodians mtorres, jkim, nshah, JoniS and three searches (`Harassment-Complaints`, `Termination-Records`, `Background-Check-PII`) feeding three review sets.

> "A real case takes hours to set up. The config deploys two complete cases — custodians, holds, searches, review sets — in one call. Your legal team can clone this structure the next time HR flags a departure or an incident fires. One workflow from 'we think something happened' to 'here's the legal production'. No bouncing between mailbox tools, SharePoint admin, and manual exports."

---

## Act 5: Communication Compliance / DSPM for AI — "Policy for what AI sees" (3 min)

**Portal:** Purview → DSPM for AI → Recommendations → Control Unethical Behavior in AI

> "DLP is about what's in the content. The traditional Communication Compliance template — Supervisory Review — was retired. Its replacement on the modern Purview surface is a DSPM-for-AI Know Your Data collection policy, scoped to Copilot's `UploadText` / `DownloadText` activity. That's what `PVLab-Inappropriate Text Policy` deploys in this lab."

**Show:**

- The KnowYourData feature configuration in DSPM for AI
- Sample Copilot interaction events flowing in (if Copilot DSPM is rolled out in this GCC tenant)
- Reviewer / remediation flow under DSPM for AI → Recommendations

**GCC caveat to mention up front:**

> "DSPM-for-AI Copilot enforcement is rolled out unevenly in GCC compared to commercial — same caveat as our GCC `ai` profile that says SIT-based Copilot prompt blocking is commercial-only. The collection policy deploys cleanly here, but the full review/remediation flow depends on Copilot DSPM being live in your specific GCC tenant. Worth a 5-minute portal walk before you commit to this for a customer demo."

---

## Act 6: Insider Risk — "Behavior over time, not a single event" (5 min)

**Portal:** Purview → Insider Risk Management → Policies

**Show the 4 policies:**

| Policy | Scenario | Scope |
|---|---|---|
| `PVLab-Departing User Data Theft` | Intellectual Property Theft | Priority group: `PVLab-Executives` |
| `PVLab-General-Data-Leaks` | Leak of Information | All users |
| `PVLab-Priority-Executive-Data-Exfil` | High-Value Employee Data Leak | Priority group: `PVLab-Executives` |
| `PVLab-Security-Policy-Violations` | Security Policy Violation | All users |

> "DLP catches an event. Insider Risk catches a pattern. Four policies running in parallel: a baseline general-leak policy on everyone, two priority-user variants scoped to `PVLab-Executives` (deliberate overlap — they fire on different scenarios with complementary risk-scoring signals), and a security-policy-violation policy that surfaces Defender for Endpoint alerts."

**Detection signal mix to call out:**

- File-activity indicators (download, share, copy-to-removable, print)
- Email-attachment-to-external-recipient indicators
- Triggering events: `HrEvent`, `AzureAccountDeleted`, `UserPerformsExfiltrationActivity`, `DlpPolicyMatchHighSeverity`, `DefenderForEndpointAlert`

**GCC caveats to mention up front:**

> "Two callouts. First, `HrEvent` only fires if you've wired up an HR data connector in Purview — without one, the departing-user policy still runs on Entra `AzureAccountDeleted` and exfiltration-activity triggers, but the canonical HR-driven trigger is dark. Second, the Defender-for-Endpoint indicators require DfE integration; without it, the deployer falls back to deploying the policy without those indicators and logs a warning. Configure them manually under Purview → Insider Risk Management → Settings → Policy indicators if you want them on."

---

## Act 7: Conditional Access — "Identity guardrails in report-only" (3 min)

**Portal:** Microsoft Entra ID → Security → Conditional Access

**Show the 3 policies (all `enabledForReportingButNotEnforced`):**

| Policy | Control |
|---|---|
| `PVLab-Require-MFA-AllUsers` | Require MFA for all users / all cloud apps |
| `PVLab-Block-HighRisk-SignIns` | Block sign-ins flagged High by Identity Protection |
| `PVLab-Require-Compliant-Device` | Require Intune-compliant or hybrid-joined device |

> "Three identity guardrails — MFA, risk-blocking, and device compliance — deployed in report-only so the lab does not lock anyone out. Switch any of them to On in Entra ID → Security → Conditional Access only after validating session impact in report-only telemetry."

**GCC caveat to mention up front:**

> "`Require-Compliant-Device` will record zero telemetry on a fresh demo tenant — there are no Intune-enrolled or hybrid-joined devices to evaluate. To see signals, enroll one device in Intune (or HAADJ) and sign in from it."

---

## Act 8: Audit Configuration — "Seven saved searches that match the lab's signals" (3 min)

**Portal:** Purview → Audit → Recent searches

**Show:** Unified audit logging is enabled (idempotent — the deployer skips if it's already on). Seven named saved searches are validated against the audit log:

| Search | Operations |
|---|---|
| `PVLab-DLP-Match-Audit` | DlpRuleMatch |
| `PVLab-DLP-Override-Audit` | DlpRuleUndo |
| `PVLab-File-Access-Audit` | FileAccessed, FileDownloaded, FileModified, FileUploaded |
| `PVLab-Sharing-Audit` | SharingInvitationCreated/Accepted, AnonymousLinkCreated, SecureLinkCreated, SharingSet |
| `PVLab-Mailbox-Permission-Audit` | Add/Remove-MailboxPermission, New/Set-InboxRule |
| `PVLab-Admin-Role-Audit` | Add/Remove role member, Add/Delete user |
| `PVLab-Sign-In-Failure-Audit` | UserLoginFailed |

> "Every signal you've seen in the previous acts ends up in the unified audit log. These seven searches give your investigators starting points that match the lab's surface area — you can clone any of them, narrow by user or date, and export."

---

## The integration moment (1 min)

> "You've seen eight workloads. Here's the thing to take away — they're not eight products. They're eight views of the same underlying classification + audit stream.
>
> - A document gets **auto-labeled** as Confidential Recipients-Only because it has an SSN.
> - That label triggers **DLP** when someone tries to send it externally.
> - **Retention** keeps it 7 years if it's a financial record, 1 year if it's a legal hold.
> - When a case opens, **eDiscovery** freezes the mailbox and seeds review sets.
> - If the conversation around it turns hostile, **DSPM-for-AI / Communication Compliance** flags it.
> - If the user starts downloading lots of labeled content, **Insider Risk** escalates their score — extra fast if they're an executive.
> - **Conditional Access** keeps the identity perimeter aligned in report-only until you're ready to enforce.
> - **Audit** ties all eight together with named searches.
>
> One label drove eight enforcement paths. That's the point."

---

## Natural Follow-Ups

1. **AI governance lab on GCC** (`-LabProfile ai -Cloud gcc`) — extend the foundation with Copilot DLP (label-only on GCC), Shadow AI (Endpoint DLP), and IRM AI-usage policies. Note: SIT-based Copilot prompt blocking is commercial-only.
2. **HR data connector** — wire up Purview's HR connector so `HrEvent` triggering events actually fire and the departing-user IRM policy hits its canonical signal.
3. **Defender for Endpoint** — turn on DfE so the IRM `DefenderForEndpoint*` indicators light up.
4. **Intune enrollment** — enroll demo devices so `PVLab-Require-Compliant-Device` records telemetry.
5. **DSPM for AI** — oversharing discovery and remediation across SharePoint and OneDrive on the GCC tenant.

---

## Objection Handling

**Q: "Sentinel integration?"**
> "Sentinel for GCC requires Azure Government endpoints and separate connector registrations — outside the scope of this lab. The capability profile gates it as `unavailable` so the deployer refuses to provision it. Sentinel + Purview is commercial-only in this lab today."

**Q: "GCC-High or DoD?"**
> "Not supported by this lab. We target GCC Moderate, which uses worldwide Graph and portal endpoints. GCC-High and DoD use Azure US Government endpoints and need different Exchange / Graph environment names — covered by the codebase's switch statements but no validated config ships for those clouds yet."

**Q: "We have some of these policies deployed already. Will this overwrite?"**
> "No. Every resource is prefixed `PVLab-` and is idempotent — running the deploy twice is a no-op on existing resources, and `Remove-Lab.ps1` only removes what this lab created. Your existing policies are untouched."

**Q: "Why are you using pre-existing users instead of creating new ones?"**
> "GCC tenant licensing churn — we don't want a deploy/teardown cycle to consume and release G5 (GCC) seats every time. The eight demo accounts already exist in the demo tenant; the deployer references them by UPN and only creates the `PVLab-Executives` / `PVLab-Finance-Team` / `PVLab-Legal-Team` groups on top."

**Q: "How long does a fresh deploy take?"**
> "10–15 minutes end-to-end on a clean GCC tenant — slightly longer than commercial because some Purview cmdlets have higher latency in GCC. Test data (10 sample emails + 6 OneDrive documents) runs at the end."

**Q: "Can I deploy without the test data?"**
> "Yes — toggle `workloads.testData.enabled` to `false` in `configs/gcc/basic-demo.json` before deploying. Note that test emails cannot be recalled and uploaded documents persist until manually deleted; `Remove-Lab.ps1` intentionally no-ops on TestData removal."

**Q: "Can I run the smoke test against this?"**
> "Yes — `./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -Cloud gcc`. It exercises all four DLP policies via Exchange (sendMail) and OneDrive (file upload). Teams chat traffic is not exercised by the smoke test — Teams DLP signals must be validated manually."

---

## Demo Environment Quick Reference

| Component | Count | Examples |
|---|---|---|
| Test users (pre-existing) | 8 | mtorres, mahmed, nshah, opark, DebraB, NestorW, JoniS, jkim |
| Groups | 3 | PVLab-Executives, PVLab-Finance-Team, PVLab-Legal-Team |
| Sensitivity labels | 2 parents + 10 sublabels | Confidential (5), Highly Confidential (5) |
| Auto-label policies | 2 | SSN → Confidential Recipients-Only; EIN/IBAN/SWIFT → Confidential All-Employees |
| DLP policies | 4 | US PII, Financial, HR Case, Workplace Health |
| Retention policies | 2 | Financial Records (7y, retain+delete), Legal Hold (1y, retain only) |
| eDiscovery cases | 2 | Data-Breach-Investigation, HR-Investigation (with searches + review sets) |
| Communication Compliance / DSPM for AI | 1 | Inappropriate Text Policy (KnowYourData feature config) |
| Insider Risk policies | 4 | Departing User Data Theft, General-Data-Leaks, Priority-Executive-Data-Exfil, Security-Policy-Violations |
| Conditional Access policies | 3 (report-only) | Require-MFA-AllUsers, Block-HighRisk-SignIns, Require-Compliant-Device |
| Audit saved searches | 7 | DLP-Match, DLP-Override, File-Access, Sharing, Mailbox-Permission, Admin-Role, Sign-In-Failure |
| Test emails | 10 | PII, financial, medical, harassment, eDiscovery-keyword content |
| Test documents (OneDrive) | 6 | Q4 Financials, Customer Master List, Patient Health Records, HR Termination Packet, Legal Discovery Notes, Departing-Employee Files |

**Deploy / teardown:**

```powershell
./Deploy-Lab.ps1 -Cloud gcc -LabProfile basic -TenantId <tenant-guid>
./Remove-Lab.ps1 -Cloud gcc -LabProfile basic -Confirm:$false -TenantId <tenant-guid>
```
