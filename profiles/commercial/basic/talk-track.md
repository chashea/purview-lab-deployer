# Basic Purview Lab — Customer Talk Track

## Overview

**Duration:** 20–30 minutes (expandable to 60 with hands-on)
**Audience:** CISO, Compliance leadership, IT decision-makers new to Microsoft Purview
**Goal:** Show the core Purview compliance stack end-to-end — labels, DLP, retention, eDiscovery, communication compliance, insider risk — on a realistic data set. No AI-specific scenarios; this is the foundation everything else builds on.

**Exec tagline:** "This is what Purview looks like when it's doing its job — classifying, protecting, retaining, and investigating your data, with a single policy surface and a single audit trail."

---

## Opening (2 min)

> "Every compliance conversation eventually lands on the same five questions:
> 1. Do we know what data we have?
> 2. Is it labeled and protected?
> 3. Can we stop it from leaving?
> 4. Can we keep what we need to keep, and delete what we need to delete?
> 5. If something goes wrong, can we find out who did what, and build a case?
>
> That's the whole Purview story. This lab deploys a working version of each piece on the same tenant — one config, one command, removable. Let's walk through it."

---

## The demo personas (1 min)

**Show:** Purview → Settings → Role groups (or Entra → Users filtered to `PVLab-`)

| User | Role | Why they matter |
|---|---|---|
| rtorres | Chief Compliance Officer | The admin driving the lab |
| mchen | Finance Analyst | Generates financial records (retention + DLP) |
| nbrooks | General Counsel | Legal privilege content (labels + eDiscovery) |
| dokafor | IT Manager | Target of insider-risk monitoring |
| sreeves | HR Director | Handles case data (SSN + medical) |
| jblake, msullivan, pnair | Sales / Marketing / Eng | Everyday-user volume |

**Groups:** `PVLab-Executives`, `PVLab-Finance-Team`, `PVLab-Legal-Team` — the basic scoping model every Purview workload inherits.

> "Eight users, three groups. Enough variety to show group-based scoping without getting lost in a huge directory."

---

## Act 1: Sensitivity Labels — "Classify once, protect everywhere" (5 min)

**Portal:** Purview → Information Protection → Labels

**Show the taxonomy:**

| Parent | Sublabels | Use case |
|---|---|---|
| Confidential | Internal, Recipients-Only, Anyone-No-Forwarding, Regulated-Data, Vertical-Specific | Everyday sensitive business content |
| Highly Confidential | Internal, Recipients-Only, Anyone-No-Forwarding, Regulated-Data, Vertical-Specific | Restricted content (PII, PCI, PHI, board-only) |

> "Two parent labels, ten sublabels. Flat enough that users don't freeze at the dropdown, rich enough to express real protection tiers. Each sublabel carries its own encryption, watermarking, and access rules — the user picks the label, the platform does the enforcement."

> **Note on `Confidential\Internal`:** intentionally unencrypted. Internal-use marking provides classification + footer/header visibility and feeds DLP/Insider Risk signals without the operational overhead of crypto. Every other sublabel is encrypted.

**Show the three auto-label policies:**
- SSN auto-apply → `Highly Confidential\Regulated-Data`
- Credit Card auto-apply → `Highly Confidential\Regulated-Data`
- EIN / IBAN / SWIFT auto-apply → `Confidential\Internal`

> "Users don't need to remember to label. When they save a document that contains an SSN or credit card, Purview applies the label automatically. That label then drives everything downstream — DLP rules, retention, Copilot access, Sentinel signals."

---

## Act 2: DLP — "Five policies covering the regulated-data footprint" (5 min)

**Portal:** Purview → Data Loss Prevention → Policies

**Show the 5 policies:**

| Policy | Locations | Scope | What it catches |
|---|---|---|---|
| US PII Protection | Exchange, SharePoint, OneDrive, Teams | All users | Messages or files with ≥5 SSNs or credit cards (bulk leak) |
| Financial Data Protection | Exchange, SharePoint, OneDrive, Teams | `PVLab-Finance-Team` | Bank account or credit card content from Finance |
| HR Case Data Protection | Exchange, SharePoint, OneDrive, Teams | `PVLab-Legal-Team` | SSN or bank-account data in legal/HR communications |
| Workplace Health Record Protection | Exchange, SharePoint, OneDrive, Teams | All users | SSN + medical keyword proximity |
| Confidential Label Egress Block | Exchange, SharePoint, OneDrive, Teams | All users | Anything labeled `Highly Confidential\Regulated-Data` going external |

> "Five policies, different thresholds for different business units. HR and Legal get a threshold of 1 — every case matters. The org-wide US PII rule uses ≥5 — catch the bulk leak, not the one-off. The last policy is the integration moment: anything auto-labeled Regulated-Data is automatically blocked from external egress. One policy, one label, no SIT lookup needed at evaluation time."

**Show what a DLP hit looks like:**
- Policy tip in Outlook ("This message contains sensitive info and can't be sent to external recipients")
- Policy tip in Word/Excel when opening a file
- Alert in Purview → DLP → Alerts

> "The user sees the policy tip before they hit send. The compliance team sees the alert after. Same event, two audiences."

---

## Act 3: Retention — "Keep what you need, delete what you don't" (3 min)

**Portal:** Purview → Data Lifecycle Management → Retention Policies

**Show the 2 policies:**

| Policy | Duration | Scope |
|---|---|---|
| Financial Records Retention | 7 years | Finance-Team content in Exchange + SharePoint |
| Legal Hold | 1 year | Legal-Team + flagged content |

> "Two time horizons for two regulatory regimes. Finance content lives 7 years because SOX says so. Legal-team holds are 1 year. Deleted users' content is preserved automatically — no admin intervention. Both policies are automatic — no user decisions, no forgotten retention tags."

---

## Act 4: eDiscovery — "From alert to legal production" (4 min)

**Portal:** Purview → eDiscovery → Cases → `PVLab-Data-Breach-Investigation`

**Show the case structure:**
- **Custodians:** mchen, jblake, pnair, msullivan (pre-attached — the people under investigation)
- **Hold:** all their mailboxes + OneDrive sites frozen
- **Searches:** Financial-Records, PII-Exfil, Suspicious-Activity (pre-built queries on sensitive terms)
- **Review sets:** one per search, ready for attorney review

> "A real case takes hours to set up. The config deploys the whole thing — custodians, hold, searches, review sets — in one call. Your legal team can clone this structure the next time HR flags a departure or an incident fires."

**Show:** Review set → filtered results → export as PST or CSV

> "One workflow from 'we think something happened' to 'here's the legal production'. No bouncing between mailbox tools, SharePoint admin, and manual exports."

**Bonus case:** `PVLab-HR-Investigation` — same shape, different custodians (rtorres, pnair, nbrooks, msullivan), scoped to harassment / termination / background-check searches. Use it to show how the same pattern repeats per investigation type.

---

## Act 5: Communication Compliance — "Visibility into AI conversations" (3 min)

**Portal:** Purview → DSPM for AI → Recommendations / Activity explorer

> "DLP is about what's in the content. Communication Compliance, in its current shape, is about visibility into how people interact with AI — Copilot prompts, prompt-and-response pairs, and traffic to enterprise AI apps. The lab deploys one DSPM-for-AI collection policy: `Workplace AI Activity Monitoring`. That gives the compliance team a queryable activity stream they can review, build trainable classifiers on top of, or wire into Insider Risk."

**Show:**
- DSPM for AI → Activity explorer (queryable Copilot prompts/responses)
- Recommendations page (`Control Unethical Behavior in AI`, etc.) — the policy is the data ingestion; the review queue and remediation workflows are completed in the portal.

> "The legacy `SupervisoryReviewPolicy` cmdlets that powered classic offensive-language reviews are retired. DSPM-for-AI is where Microsoft is investing — it inherits the same Communication Compliance review experience but with AI activity as the primary signal."

> **Demo note:** the lab's seeded test emails won't trigger DSPM-for-AI on their own — the policy reads Copilot prompts and responses, not mailbox content. To see signals in Activity explorer, sign in as one of the test users and issue a Copilot prompt that includes PII (e.g., *"Summarize this customer record: SSN 123-45-6789, CC 4111-1111-1111-1111"*). The activity will appear in DSPM for AI within a few minutes.

---

## Act 6: Insider Risk — "Behavior over time, not a single event" (4 min)

**Portal:** Purview → Insider Risk Management → Policies

> "DLP catches an event. Insider Risk catches a pattern. The lab ships four IRM policies that overlap and reinforce each other:
> - `PVLab-Departing User Data Theft` — uses the *Data theft by departing users* template; priority on Executives.
> - `PVLab-General-Data-Leaks` — broad data-leak signals across all users (DLP-high-sev triggering).
> - `PVLab-Priority-Executive-Data-Exfil` — elevated scoring for the Executives priority group.
> - `PVLab-Security-Policy-Violations` — Defender-for-Endpoint-driven (malware, suspicious endpoint activity).
>
> Together they show the layering pattern: a baseline policy for everyone, plus priority-user policies for the people whose risk score should escalate faster."

**Wizard-step defaults to call out** (matches how most customers configure in the portal):
- **Users and groups:** `Departing User Data Theft` and `Priority-Executive-Data-Exfil` scope to `PVLab-Executives`. The other two are tenant-wide. Easy story for "baseline + priority overlay".
- **Content to prioritize:** one randomly-selected sensitivity label + one SIT + one trainable classifier (skip SharePoint sites — content-specific and brittle across tenants).
- **Detection options:** every indicator and triggering event the template exposes is selected — maximizes the signal surface for the demo.

> "The policy enriches with HR departure signals from your identity system. When someone's 30 days out and their copy-to-personal-email count jumps 5x, the user's IRM score escalates and appears on the investigator queue."

---

## Act 7: Identity + Audit baseline (90 sec)

**Portal:** Entra → Conditional Access (report-only) and Purview → Audit → Saved searches

> "Two pieces that aren't strictly Purview but every compliance lab needs them:
>
> - **Conditional Access** — three policies deploy in *report-only* mode: require MFA, block high-risk sign-ins, require compliant device. Report-only means they evaluate and log without enforcing. Flip to enabled when you're ready.
> - **Audit** — seven saved searches across DLP matches, DLP overrides, file access, sharing, mailbox permissions, admin role changes, sign-in failures. The searches themselves are the demo — they show what's worth saving as a recurring investigation pattern.
>
> Both are deployed because every Purview workload above generates events that land in audit, and Conditional Access is what makes 'compliant device required' real for sensitive content."

---

## The integration moment (1 min)

> "You've seen six workloads. Here's the thing to take away — they're not six products. They're six views of the same underlying classification + audit stream.
>
> - A document gets **auto-labeled** as Regulated-Data.
> - That label triggers **DLP** when someone tries to send it externally.
> - **Retention** keeps it 7 years.
> - When a case opens, **eDiscovery** freezes the mailbox.
> - If the conversation around it turns hostile, **Communication Compliance** flags it.
> - If the user starts downloading lots of labeled content, **Insider Risk** escalates their score.
>
> One label drove six enforcement paths. That's the point."

---

## Natural Follow-Ups

1. **Copilot DLP Guardrails** (separate lab profile) — extend this foundation to block Copilot from processing sensitive prompts and labeled content.
2. **Shadow AI Prevention** (separate lab profile) — extend DLP to endpoint + network to catch paste/upload to ChatGPT, Claude, Gemini.
3. **Sentinel Integration** (separate lab profile) — stream DLP and IRM signals into Sentinel for SOC correlation.
4. **AI Security** (integrated lab profile) — the whole AI story (Copilot + Shadow AI + Sentinel) under one prefix.
5. **DSPM** — oversharing discovery and remediation across your SharePoint and OneDrive footprint.

---

## Objection Handling

**Q: "We have a GCC/GCC-High tenant — does this still work?"**
> "Commercial is the default. GCC has its own config variant with the same workloads minus a couple of feature-parity gaps. GCC-High isn't supported by this lab today."

**Q: "How do we scope this to one department first, then expand?"**
> "Every workload supports group-based scoping. The config already uses `PVLab-Finance-Team` and `PVLab-Legal-Team` as example scopes. Replace the group names with yours, run a single department first, measure, expand."

**Q: "We already have some of these policies deployed. Will this overwrite?"**
> "No. Every resource is prefixed `PVLab-` and is idempotent — running the deploy twice is a no-op on existing resources, and `Remove-Lab.ps1` only removes what this lab created. Your existing policies are untouched."

**Q: "How long does a fresh deploy take?"**
> "5–10 minutes end-to-end on a clean tenant, most of it waiting on the Exchange Online + Graph sessions. Test data (6 sample emails) runs at the end."

**Q: "Can I deploy without creating test users?"**
> "Yes — `-SkipTestUsers` flag. The rest of the lab deploys against your existing identities. Group-based scoping still works because the deploy creates the groups (`PVLab-Executives`, etc.) and you can populate them however you want."

---

## Demo Environment Quick Reference

| Component | Count | Examples |
|---|---|---|
| Test users | 8 | rtorres (CCO), mchen (Finance), nbrooks (Legal), dokafor (IT), sreeves (HR), jblake/msullivan/pnair |
| Groups | 3 | PVLab-Executives, PVLab-Finance-Team, PVLab-Legal-Team |
| Sensitivity labels | 2 parents + 10 sublabels | Confidential (5), Highly Confidential (5) |
| Auto-label policies | 3 | SSN, Credit Card → Highly Confidential\Regulated-Data; EIN/IBAN/SWIFT → Confidential\Internal |
| DLP policies | 5 | US PII (≥5), Financial (Finance scope), HR Case (Legal scope), Workplace Health, Label Egress Block |
| Retention policies | 2 | Financial (7y), Legal Hold (1y) |
| eDiscovery cases | 2 | Data-Breach-Investigation, HR-Investigation |
| Communication Compliance | 1 | Workplace AI Activity Monitoring (DSPM-for-AI collection) |
| Insider Risk policies | 4 | Departing User, General Leaks, Priority Exec Exfil, Security Violations |
| Conditional Access | 3 (report-only) | Require MFA, Block High-Risk, Require Compliant Device |
| Audit searches | 7 | DLP match/override, file access, sharing, mailbox perms, admin role, sign-in failures |
| Test emails | 7 | PII, financial, sensitive content, bulk SSN dump |

**Deploy / teardown:**

```powershell
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic -TenantId <tenant-guid>
./Remove-Lab.ps1 -Cloud commercial -LabProfile basic -Confirm:$false -TenantId <tenant-guid>
```
