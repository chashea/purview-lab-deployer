# Shadow AI Prevention Demo — Customer Talk Track

## Overview

**Duration:** 15-20 minutes
**Audience:** CISO, Security/Compliance leadership, IT decision-makers
**Goal:** Show how Microsoft Purview provides layered protection against shadow AI data risks — from visibility to enforcement to investigation.

---

## Opening (2 min)

> "Today I want to show you how Microsoft Purview addresses what we're seeing as the #1 emerging data risk across enterprises — shadow AI.
>
> Your employees are already using ChatGPT, Claude, Gemini, and other AI tools. Some of that usage is productive, but some of it is putting sensitive data at risk. The challenge isn't blocking AI entirely — it's getting visibility, putting guardrails in place, and steering users toward sanctioned tools like Microsoft Copilot.
>
> What I've deployed here is a fully automated Purview lab that demonstrates a tiered governance model for AI data protection. Let me walk you through it."

---

## Act 1: Discovery — "What's happening today?" (3 min)

**Portal:** Microsoft Purview > Audit > Search

> "The first question every CISO asks is: 'Are my people using shadow AI, and what are they sharing?'
>
> We've pre-configured three audit searches that answer this immediately:"

**Show:**
1. **Copilot Activity Audit** — CopilotInteraction events
2. **DLP Policy Match Audit** — DlpRuleMatch events across AI workloads
3. **External AI App Access Audit** — FileUploaded events to external destinations

> "This gives you a baseline. You can see who's interacting with AI tools, what data is being shared, and where the risk concentrations are. No enforcement yet — just visibility."

**Transition:** "Now that we know the problem, let me show you how we protect against it."

---

## Act 2: Tiered DLP — "Graduated enforcement" (5 min)

> "We don't believe in a binary 'block everything' approach. Instead, we deployed a tiered model that matches enforcement to risk level."

### Tier 1: Visibility (Low friction)
**Show:** GenAI Prompt PII Protection policy

> "At the lowest tier, we're detecting sensitive data — SSNs, credit card numbers — in AI interactions. This runs in audit-only mode. Users aren't interrupted, but every match is logged. This is your early warning system."

### Tier 2: Guardrails (Moderate friction)
**Show:** GenAI Financial and Payroll Guardrail policy

> "For financial data — bank accounts, payroll records — we add a speed bump. Users see a policy tip that says 'You're sharing sensitive data with an AI tool. Provide a business justification to continue.' This catches accidental sharing without blocking legitimate use."

### Tier 3: Hard Block (Maximum protection)
**Show:** External AI Upload Risk Signals policy + Endpoint AI Site Restrictions

> "For the highest-risk scenarios — medical data, regulated content — we enforce a hard block. If someone tries to paste protected health information into ChatGPT, Defender for Endpoint intercepts it at the browser level. They see a clear message directing them to use Copilot instead."

**Show blocked domains list:**
- chat.openai.com, chatgpt.com, claude.ai, gemini.google.com, perplexity.ai, poe.com, huggingface.co/chat

> "This isn't about blocking AI. It's about blocking the *wrong* AI with the *wrong* data."

### Tier 4: Label-based restrictions
**Show:** Labeled Data AI Restriction policy

> "We also enforce based on sensitivity labels. Content labeled 'Highly Confidential — AI Blocked from External Tools' or 'AI Regulated Data' cannot be shared to external AI destinations at all. The label travels with the document."

---

## Act 3: Adaptive Protection — "Risk-aware enforcement" (3 min)

**Show:** Adaptive AI Protection by Risk Level policy (3 rules)

> "Here's where it gets intelligent. We don't treat all users the same. We've connected DLP to Insider Risk Management to create adaptive enforcement."

| User Risk Level | Enforcement |
|---|---|
| Minor (normal) | Audit only — no friction |
| Moderate (some signals) | Warn with justification required |
| Elevated (high risk) | Hard block — no override |

> "If an employee starts showing risky behavior — repeated policy violations, unusual data access patterns — their enforcement automatically tightens. A departing employee or someone flagged by Insider Risk gets blocked from AI tools entirely, while a normal user gets a light-touch audit."

**Show:** 3 Insider Risk policies feeding into this:
- Shadow AI Risky Usage Watch
- AI Data Exfiltration Watch
- Departing User AI Risk

> "The risk score escalates automatically: minor to moderate to elevated. The DLP policies respond in real-time."

---

## Act 4: Sensitivity Labels — "Protection that travels with data" (2 min)

**Show:** Label hierarchy

> "We've deployed AI-specific sensitivity labels that make the governance model concrete."

| Label | Protection | AI Behavior |
|---|---|---|
| Confidential > AI Internal Use | Footer marking | Allowed in Copilot, monitored |
| Confidential > AI Restricted Recipients | Encryption | Named recipients only |
| Highly Confidential > AI Blocked from External Tools | Encryption + marking | Blocked from all external AI |
| Highly Confidential > AI Regulated Data | Encryption + marking | Blocked, auto-labeled on SSN detection |

> "The auto-label policy catches SSNs in Exchange and SharePoint and automatically applies the 'AI Regulated Data' label. From that point, DLP enforces the restriction — no manual classification needed."

---

## Act 5: Communication Compliance — "Monitoring sanctioned AI" (2 min)

**Show:** 3 Communication Compliance policies

> "Even when users are in sanctioned tools like Copilot, you need visibility into what they're discussing."

- **External AI Prompt Sharing Monitoring** — flags business users sharing data externally
- **Sensitive Business Data in AI Prompts** — catches finance, HR, and IT staff disclosing sensitive business data
- **Compliance Violations in AI Content** — detects compliance-related violations across teams

> "These create a review queue for your compliance team. It's not about blocking — it's about knowing what's happening so you can respond."

---

## Act 6: Investigation — "When something goes wrong" (2 min)

**Show:** eDiscovery case — Shadow-AI-Incident-Review

> "When you do have an incident, everything is already in place. We have a pre-configured eDiscovery case for a shadow AI investigation."

- **Custodians:** Security Architect, Privacy Counsel, HR Director
- **Hold query:** `"AI" OR "copilot" OR "chatbot" OR "prompt"`
- **Search query:** `"public AI" OR "external AI" OR "paste" OR "upload"`

> "All AI-related communications are preserved under legal hold with a 3-year retention policy. The 1-year retention on general AI interactions gives you audit history, while the 3-year policy on incident evidence meets regulatory requirements."

---

## Closing (1 min)

> "So to recap — what you've seen is a complete governance framework for shadow AI:
>
> 1. **Discover** — Audit logs and Cloud Discovery show you what's happening
> 2. **Protect** — Tiered DLP policies match enforcement to risk level
> 3. **Adapt** — Insider Risk scores drive dynamic enforcement
> 4. **Label** — Sensitivity labels make protection portable
> 5. **Monitor** — Communication Compliance covers sanctioned AI usage
> 6. **Investigate** — eDiscovery and retention are ready for incidents
>
> This entire environment was deployed programmatically in under 15 minutes. It's config-driven, repeatable, and tears down cleanly. We can customize the policies, personas, and enforcement levels for your specific environment."

---

## Anticipated Questions

**Q: "Does this block Copilot too?"**
> "No. The enforcement is intentionally asymmetric. Copilot interactions are monitored via Communication Compliance but allowed. External AI tools get tiered enforcement. The goal is to steer users toward Copilot, not block AI entirely."

**Q: "What about BYOD / unmanaged devices?"**
> "Endpoint DLP requires Defender for Endpoint on managed devices. For unmanaged devices, Conditional Access policies can require MFA or block access to AI apps entirely based on device compliance state."

**Q: "How long to deploy this in production?"**
> "The automated deployment takes about 15 minutes. Policy tuning and rollout planning typically takes 2-4 weeks in a phased approach — start with audit-only, then enable guardrails, then enforcement."

**Q: "What licenses are required?"**
> "Microsoft 365 E5 or E5 Compliance for the full stack. E3 + E5 Compliance add-on also works. Copilot requires a separate Copilot for Microsoft 365 license."

**Q: "Can we scope this to specific departments first?"**
> "Absolutely. The DLP policies support group-based scoping. In this demo, the External AI Upload policy is already scoped to the Privileged Data Owners group. You can roll out department by department."

---

## Demo Environment Quick Reference

| Component | Count | Examples |
|---|---|---|
| Test users | 8 | Alex Harper (Marketing), Victor Cho (Finance), Leah Ramirez (Legal), ... |
| Security groups | 3 | AI-Governance, Privileged-Data-Owners, Business-Users |
| DLP policies | 6 | PII visibility, Financial guardrail, External AI block, Label restriction, Endpoint block, Adaptive |
| DLP rules | 12 | SSN/CC detection, bank accounts, medical terms, labeled data, risk-tiered |
| Sensitivity labels | 4 sublabels | AI Internal Use, AI Restricted Recipients, AI Blocked, AI Regulated Data |
| Comm compliance | 3 | Prompt sharing, business data, compliance violations |
| Insider risk | 3 | Shadow AI usage, data exfiltration, departing users |
| Retention | 2 | 1-year audit, 3-year incident evidence |
| eDiscovery | 1 case | Shadow AI incident investigation |
| Test emails | 6 | Seeded with SSNs, credit cards, bank accounts, medical terms, API keys |
| Test documents | 3 | Financial forecast, customer export, engineering specs |
