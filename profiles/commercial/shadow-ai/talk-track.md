# Shadow AI Prevention Demo — Customer Talk Track

## Overview

**Duration:** 20–30 minutes (expandable to 75–90 with hands-on)
**Audience:** CISO, Security/Compliance leadership, IT decision-makers, AI governance stakeholders
**Goal:** Show how Microsoft Purview provides layered protection against shadow AI — discovery, graduated enforcement, adaptive risk response, and sanctioned-tool steering.

**Exec tagline:** "We're not blocking AI. We're blocking the *wrong* AI with the *wrong* data — and steering users to the sanctioned path."

---

## Opening (2 min)

> "Shadow AI is the top data-risk vector we're seeing across enterprises. Your people are already using ChatGPT, Claude, Gemini, and increasingly agentic tools built on top of them. Some of that usage is productive. Some of it is pasting SSNs, payroll routing numbers, and customer records into public AI endpoints.
>
> The wrong response is 'block everything.' That just drives it underground. The right response is visibility, graduated guardrails, and a sanctioned path — Microsoft 365 Copilot — where the same work gets done with enterprise data protection.
>
> Everything you're about to see was deployed programmatically in about 15 minutes from a config file. Repeatable, customizable, tears down cleanly."

---

## Act 1: Discovery — "What's happening today?" (3 min)

**Portal:** Microsoft Purview > Audit > Search

> "The first CISO question is always: 'Is this even a problem in my tenant, and what are people sharing?'"

**Show three pre-configured audit searches:**
1. **Copilot Activity Audit** — `CopilotInteraction` events across users
2. **DLP Policy Match Audit** — every DLP rule match, AI-related or not
3. **External AI App Access Audit** — `FileUploaded` events to external destinations, browser events to AI sites

> "This is baseline visibility. No enforcement yet, just evidence. You see which users touch which AI tools, what data types are in play, and where the concentration of risk sits — typically Finance, HR, Engineering."

**Bonus:** If DSPM for AI is activated, jump to **DSPM for AI > Reports > Sensitive interactions per generative AI app** and show the aggregated picture. That's the Microsoft-recommended posture surface.

**Transition:** "We know what's happening. Now let me show you what we do about it."

---

## Act 2: Tiered DLP — "Graduated enforcement" (6 min)

> "Binary block doesn't work. Users route around it and productivity takes a hit. We deployed a four-location, risk-tiered model."

### Location 1: Devices — Endpoint DLP (paste/upload)

**Show:** `Shadow AI - Endpoint Protection` policy

> "On managed devices, Endpoint DLP watches paste and upload activity in browsers. If someone tries to paste a customer record into ChatGPT, Microsoft Defender for Endpoint intercepts at the device level. They get a clear policy tip: 'This data can't be shared to external AI — use Copilot instead.'"

### Location 2: Browser — Browser Data Security (inline)

**Show:** `Shadow AI - Browser Prompt Protection` policy

> "Inside Microsoft Edge for Business, we add an inline control that inspects text before it's submitted to a prompt field. Same SITs as the DLP stack — SSN, credit card, bank account, medical terms."

### Location 3: Network — Network Data Security (non-Edge traffic)

**Show:** `Shadow AI - Network AI Traffic` policy

> "For employees on Chrome or Firefox, or traffic leaving through non-browser apps, we extend DLP to the network layer via SASE/SSE integration. Same policy language, broader coverage."

### Location 4: CopilotExperiences — Microsoft 365 Copilot

**Show:** `Shadow AI - Copilot Prompt Protection` + `Shadow AI - Copilot Label Protection`

> "The sanctioned tool — Copilot — still gets DLP. Prompts are inspected for SITs. Files labeled Highly Confidential are excluded from Copilot's grounding data. Same guardrails, different enforcement surface. Users get a consistent experience."

**Expert callout:**

> "Notice the enforcement is *asymmetric by design*. External AI gets hard blocks and warn-with-justification. Copilot gets the same detection but with the context of enterprise controls already in place — so the friction is lower. That's how we steer behavior without breaking productivity."

**Transition:** "That's the policy surface. Now let me show you the intelligence that makes it adaptive."

---

## Act 3: Risk-Adaptive Enforcement — "Same data, different user, different response" (3 min)

> "The same DLP match doesn't mean the same thing from every user. A one-off paste from a consistent engineer is noise. The same paste from someone who's been flagged for repeated violations or is about to leave is signal."

**Show the risk-tier pattern in `Shadow AI - Endpoint Protection`:**

| User Risk Level | Rule | Enforcement |
|---|---|---|
| Elevated | Endpoint AI Block - Elevated Risk | Hard block, no override |
| Moderate | Endpoint AI Warn - Moderate Risk | Allow with justification |
| Minor | Endpoint AI Audit - Minor Risk | Audit only — no friction |

> "Same SITs, same policy. But the `insiderRiskLevel` condition pulls the user's current risk score from Insider Risk Management in real time. Block users who are escalating. Warn users on the fence. Don't friction users who are behaving."

**Show the 6 IRM policies feeding this:**

- Shadow AI Risky Usage Watch (template: *Risky AI usage*)
- AI Data Exfiltration Watch (template: *Data leaks*)
- Departing User AI Risk (template: *Data theft by departing users*)
- DSPM for AI - Detect risky AI usage
- DSPM for AI - Business User AI Risk
- DLP Correlated AI Exfiltration (correlates DLP match events into insider risk scoring)

> "Risk scores escalate automatically. Minor to Moderate to Elevated. The DLP policies respond in real time, no admin intervention."

**Wizard-step defaults applied to each IRM policy** (matches how most customers configure in the portal):
- **Users and groups:** All users and groups in your organization — no priority-user scoping
- **Content to prioritize:** one randomly-selected sensitivity label + one SIT + one trainable classifier (skip SharePoint sites — content-specific and brittle across tenants)
- **Detection options:** select all indicators and triggering events the template exposes

---

## Act 4: Labels — "Protection that travels with data" (3 min)

**Show the label hierarchy:**

| Label | AI Behavior |
|---|---|
| Confidential > All Employees | Allowed across all AI paths, audit only |
| Confidential > AI Internal Use | Allowed in Copilot, blocked externally |
| Confidential > AI Restricted Recipients | Encrypted, named-recipient only |
| Confidential > AI Regulated Data | Blocked from external AI, auto-applied on SSN/CC/Bank/IP patterns |
| Highly Confidential > AI Blocked from External Tools | Encrypted, blocked from all external AI |
| Highly Confidential > AI Regulated Data | Blocked from Copilot + external, auto-applied on SSN |

> "The auto-label policies catch SSNs, credit cards, bank accounts, and IBANs and apply the appropriate AI-Regulated-Data label automatically. From that point on, DLP enforces — including on Copilot. The label travels with the document across Exchange, SharePoint, OneDrive, and into AI grounding decisions."

---

## Act 5: Retention + Communication Compliance — "Evidence that lasts" (2 min)

**Show retention policies:**

- AI Prompt Review Retention (1 year)
- AI Incident Evidence Retention (3 years)
- Copilot Experiences Retention (1 year, targets `MicrosoftCopilotExperiences`)
- Enterprise AI Apps Retention (3 years, targets `EnterpriseAIApps` — ChatGPT Enterprise, Foundry, Entra-registered AI)
- Other AI Apps Retention (1 year, targets `OtherAIApps` — ChatGPT consumer, Gemini, DeepSeek)

> "Every AI interaction is retained per a policy that matches its risk. Regulated industries get the 3-year evidence retention automatically for anything flagged as an incident."

**Show Communication Compliance policies:**

- Shadow AI Activity Collection — review queue for AI-adjacent messages
- AI Conversation PII PHI Detection — targeted PII/PHI supervision in AI conversations

> "This is the compliance review layer. It's not about blocking — it's about having a queue where trained reviewers can catch patterns humans need to see."

---

## Act 6: Investigation — "When something goes wrong" (2 min)

**Show:** eDiscovery case `Shadow-AI-Incident-Review`

- Custodians: Security architect, Privacy counsel, HR lead
- Hold query: `"AI" OR "copilot" OR "chatbot" OR "prompt"`
- Search query: `"public AI" OR "external AI" OR "paste" OR "upload"`

> "When an incident hits — suspected IP theft involving an AI tool — everything is already under legal hold. The case opens with custodians set, search queries pre-built, and 3-year retention guaranteeing the data is still there."

---

## Closing (2 min)

> "To recap — what you've seen is a complete governance framework for shadow AI:
>
> 1. **Discover** — Audit logs, Activity Explorer, DSPM for AI reports show you what's happening today
> 2. **Enforce at 4 locations** — Devices, Browser, Network, Copilot — with the same policy language
> 3. **Adapt** — Insider Risk scores drive real-time DLP enforcement tiers
> 4. **Label** — Auto-labels make protection portable across surfaces
> 5. **Retain** — AI-specific retention policies preserve evidence for compliance
> 6. **Review** — Communication Compliance catches patterns humans need to see
> 7. **Investigate** — eDiscovery, retention, and audit tie the evidence chain together
>
> We didn't block AI. We built guardrails that meet users where they work and steer them toward Copilot. That's the Microsoft data-centric AI security model."

---

## Anticipated Questions

**Q: "Does this also block Copilot?"**
> "By design, no. Copilot is the sanctioned path — we apply DLP to it so the *same* sensitive data gets the same treatment, but the user friction is lower because Copilot runs inside your compliance boundary. External AI tools get tiered blocks. Copilot gets guardrails. The asymmetry steers behavior."

**Q: "How does this work on BYOD or unmanaged devices?"**
> "Endpoint DLP requires Defender for Endpoint on managed devices — on BYOD you fall back to Conditional Access plus Browser Data Security in Edge for Business. The two conditional-access policies in this lab block AI app access for high-sign-in-risk users and require MFA for AI app sign-ins. Combine that with Entra app registration for ChatGPT / Claude / Gemini to get full sign-in-based enforcement."

**Q: "What about non-Edge browsers?"**
> "Three complementary controls: (1) Endpoint DLP supports Chrome and Firefox via the Purview browser extension; (2) Network Data Security via your SASE/SSE provider covers any browser or app; (3) the unallowed-browsers setting can force users into Edge for sensitive work. Most customers run all three."

**Q: "Does Purview cover Entra-registered AI apps like a custom ChatGPT Enterprise deployment?"**
> "Yes. Once the app is registered in Entra, it shows up as a supported AI app across DLP, DSPM for AI, retention (`EnterpriseAIApps` location), and Communication Compliance. The DSPM for AI one-click *Secure interactions from enterprise apps* policy is the fastest way to wire this up."

**Q: "What's DSPM for AI and how does it fit?"**
> "Think of this lab as the *enforcement* surface. DSPM for AI is the *posture* surface — where oversharing still lives, which users carry most AI risk, which SharePoint sites need labeling before Copilot touches them. Enforcement + posture is the complete story. The RUNBOOK walks through activating DSPM for AI one-click policies that complement this lab."

**Q: "How long to deploy in production?"**
> "Automated deploy is 15 minutes. Rollout planning is typically 2–4 weeks in phases: audit-only first, then warn-with-justification, then enforce. Same config, change `simulationMode: false` and flip policy mode when you're ready."

**Q: "What licenses do we need?"**
> "Microsoft 365 E5 or E5 Compliance for the full Purview stack. Microsoft 365 Copilot licenses for the sanctioned-tool story. Defender for Endpoint on managed devices. Some Browser Data Security and DSPM for AI collection policies are pay-as-you-go — see MS Learn pricing."

**Q: "Can we scope this to specific departments first?"**
> "Yes. Every DLP and IRM policy supports group-based scoping. The config already scopes Privileged-Data-Owners and Business-Users groups for pilot-style rollout. Roll out department by department with the same policy logic."

**Q: "Is Shadow AI detection real-time or retrospective?"**
> "Mixed. Endpoint DLP paste/upload is real-time — the action is blocked inline. Network Data Security is real-time on the SASE side. Audit and Activity Explorer are near-real-time — matches surface within minutes. DSPM for AI reports run on a daily aggregation."

---

## Natural Follow-Ups

1. **DSPM for AI activation** — one-click policies ship most of the same controls Microsoft recommends; this lab covers the custom / scoped variants. Pair for full coverage. See RUNBOOK section 7.
2. **Defender for Cloud Apps** — app governance layer for sanctioned AI. Catalog, sanction/unsanction, risk scoring for SaaS AI tools.
3. **Security Copilot for Purview** — AI-on-AI triage for DLP alerts and IRM cases.
4. **Copilot DLP Guardrails lab** — complementary lab (`copilot-protection` profile) that focuses specifically on the Microsoft 365 Copilot surface with a narrower policy set.
5. **Entra-registered AI app catalog** — connect ChatGPT Enterprise / custom Foundry agents to Entra and inherit this lab's controls for those apps.

---

## Demo Environment Quick Reference

| Component | Count | Examples |
|---|---|---|
| Test users | 5 | rtorres, mchen, nbrooks, dokafor, sreeves |
| Security groups | 3 | AI-Governance, Privileged-Data-Owners, Business-Users |
| DLP policies | 5 | Endpoint, Browser, Network, Copilot Prompt, Copilot Label |
| DLP rules | 13 | Risk-tiered: Elevated=block, Moderate=warn, Minor=audit |
| Sensitivity labels | 2 parents + 10 sublabels | Confidential + Highly Confidential with 5 AI-specific sublabels each |
| Auto-label policies | 2 | SSN → Highly Confidential; CC/Bank/IBAN/IP → Confidential |
| Insider Risk | 6 policies | Risky AI usage, Data leaks, Departing users, DSPM correlation |
| Communication Compliance | 2 policies | Activity collection, PII/PHI detection |
| Retention | 5 policies | 1 year / 3 year, across Exchange/SharePoint/AI apps |
| eDiscovery | 1 case | Shadow AI incident investigation |
| Audit searches | 3 | CopilotInteraction, DlpRuleMatch, External AI access |
| Conditional Access | 2 policies (report-only) | Block high-risk, Require MFA |
| Test documents | 5 | Financial, Customer, Engineering, HR, AI policy draft |
| Config | `configs/commercial/shadow-ai-demo.json` | Prefix: `PVShadowAI` |
