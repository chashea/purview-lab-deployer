# Copilot DLP Guardrails — Customer Talk Track

## Overview

**Duration:** 20–30 minutes (expandable to 75–90 with hands-on)
**Audience:** CISO, Security/Compliance leadership, IT decision-makers, Copilot stakeholders
**Goal:** Show how Purview DLP enforces data boundaries for M365 Copilot — and what actually happens when those guardrails trigger.

**Exec tagline:** "We're not turning Copilot off — we're teaching it what it's allowed to see, summarize, and search."

**Feature status (per Microsoft Learn):** Label-based file blocking is GA. Prompt SIT blocking — which also prevents sensitive prompt text from being used in internal or external web searches — is in public preview and rolling out to tenants. Validate availability before demo day with `./scripts/Test-CopilotDlpReady.ps1`.

---

## Opening (2 min)

> "Copilot doesn't invent risk. It amplifies existing data exposure.
>
> In this lab, we'll let Copilot loose — then show how Purview puts it back inside the guardrails without breaking productivity.
>
> By the end of this session, you'll see how to:
> - Block Copilot from processing sensitive prompts (PII, PHI, PCI)
> - Prevent Copilot from summarizing or reasoning over labeled content
> - Stop Copilot from using sensitive data for web search
> - See the full audit trail when Copilot is constrained
>
> All of this is explicitly supported by Microsoft's Copilot + Purview enforcement model. This isn't theoretical — you'll see it happen."

---

## Phase 0: Baseline — "The before state" (5 min)

**Portal:** Microsoft 365 Copilot

> "Before we turn on any guardrails, let's see what Copilot can do with full access."

**Show:**
1. Copilot summarizing a document from SharePoint
2. Copilot answering a question based on file content
3. Copilot providing a web-backed response

> "Everything works. Copilot has access to your files, your emails, your data. That's the value proposition — but it's also the risk. Now let's add the guardrails."

**Transition:** "The question every CISO asks: How do we trust Copilot with our data?"

---

## Phase 1: Block Sensitive Prompts — "What you type matters" (10 min)

**Portal:** Microsoft Purview > DLP > Policies > `PVCopilotDLP-Copilot Prompt SIT Block`

> "The first guardrail: if a user types sensitive information directly into a Copilot prompt, DLP intercepts it. The same control stops that sensitive text from being sent to internal or external web searches — so the data never leaves the compliance boundary."

**Show the policy:**
- Location: Microsoft 365 Copilot & Copilot Chat
- Condition: Content contains sensitive info types
- 3 rules: SSN, Credit Card, PHI
- Action: Block Copilot response (and block web-search use of the sensitive prompt text)
- Scope note: typed prompt text is evaluated; uploaded file contents in prompts are not DLP-scanned
- Status: public preview — rolling out tenant-by-tenant

**Live demo:**

| Prompt | Result |
|---|---|
| "Summarize benefits for employee 078-05-1120" | Blocked — SSN detected |
| "What charges on card 4532-8721-0034-6619?" | Blocked — credit card detected |
| "Summarize treatment for diabetes mellitus" | Blocked — PHI detected |
| "What are our Q4 revenue projections?" | Normal response — no sensitive data |

> "The user sees a clear, policy-driven message — not a vague error. They know exactly why Copilot can't answer, and they know it's intentional."

> "One control, three protections: prompt blocked, internal search blocked, web search blocked. The sensitive string never leaves the guardrail."

**Transition:** "That covers what users type. Now let's talk about what Copilot can see."

---

## Phase 2: Block Labeled Files — "The label is the boundary" (10 min)

**Portal:** Microsoft Purview > DLP > Policies > `PVCopilotDLP-Copilot Labeled Content Block`

> "The second guardrail: if a file has a sensitivity label that restricts AI access, Copilot cannot summarize, reference, or reason over it. Period."

**Show the policy:**
- Location: Microsoft 365 Copilot
- Condition: Content contains sensitivity label
- 2 rules: Highly Confidential > Restricted, Highly Confidential > Regulated Data
- Action: Block

**Live demo:**

| File | Label | Copilot Response |
|---|---|---|
| Q4-Revenue-Forecast.txt | Highly Confidential > Restricted | Blocked — cannot summarize |
| Employee-Benefits-Summary.txt | Highly Confidential > Regulated Data | Blocked — auto-labeled via SSN detection |
| Unlabeled document | None | Normal response |

> "Copilot does not suggest workarounds — no 'try copy/paste' or 'try relabeling.' The enforcement is definitive."

### Expert Callout

> "Important technical note: you cannot mix sensitive info type conditions and label conditions in the same DLP rule. But you can use multiple rules in one policy, or separate policies — which is exactly what we've done here. One policy for prompt content, one for file labels."

**Transition:** "Now let's look at what security teams care about most — the evidence."

---

## Phase 3: Evidence & Investigations — "Prove it works" (5 min)

**Portal:** Microsoft Purview > Audit > Search

> "Every time Copilot is constrained by DLP, the event is recorded. Let me show you what that looks like."

**Show:**
1. **CopilotInteraction audit** — all Copilot usage
2. **DlpRuleMatch audit** — every time a Copilot prompt or file access was blocked
3. **DLP alert dashboard** — policy violations with Copilot context

**Audit record details:**
- Prompt blocked: which user, what sensitive data type, which policy
- File excluded: which file, which label, which policy
- Timestamp, device, session context

**Show eDiscovery case:**

> "If an incident needs investigation, everything is ready. The eDiscovery case has a hold query preserving Copilot-related communications and a search query for sensitive data references."

> "This is defensible AI governance. Not 'we think Copilot is safe' — 'here's the audit trail that proves it.'"

---

## Closing (2 min)

> "To recap — what you've seen today:
>
> 1. **Copilot without guardrails** — full access to everything
> 2. **Guardrail #1** — DLP blocks sensitive data in prompts (SSN, credit card, PHI) AND blocks that sensitive text from being used in internal or web searches — one policy, three protections
> 3. **Guardrail #2** — DLP blocks Copilot from labeled content (Highly Confidential)
> 4. **Full audit trail** — every blocked event is recorded and investigable
>
> We didn't turn Copilot off. We taught it what it's allowed to see, summarize, and search. That's the Microsoft data-centric AI security model.
>
> This entire environment was deployed programmatically. It's config-driven, repeatable, and tears down cleanly."

---

## Anticipated Questions

**Q: "Does this actually block Copilot, or just log it?"**
> "Both. The DLP action is 'block' — Copilot cannot return a response. And every block generates an audit record. In simulation mode, it logs without blocking, which is useful for policy tuning."

**Q: "What about prompts that are close to sensitive but not exact matches?"**
> "DLP uses the same sensitive info type detection engine as the rest of Purview — pattern matching, checksums, proximity rules, confidence levels. If it detects a valid SSN pattern with high confidence, it triggers. You can tune the confidence threshold in the rule."

**Q: "Can users override the block?"**
> "Not with these policies. The action is a hard block with no override option. For lower-sensitivity scenarios, you could configure 'allow with justification' instead. The enforcement is your choice."

**Q: "What if I want to allow Copilot for some labeled content but not others?"**
> "That's exactly why we use label-specific rules. 'Confidential > General' allows Copilot access. 'Highly Confidential > Restricted' blocks it. The label is the control surface."

**Q: "How long until DLP policies take effect on Copilot?"**
> "Plan for up to 4 hours after policy creation or change for full Copilot/Copilot Chat propagation. For demos, deploy ahead of time and verify with `Test-CopilotDlpReady.ps1`."

**Q: "What about web search? Does sensitive prompt data leak out to Bing or the open web?"**
> "No — and this is an important point. The same prompt SIT policy that blocks the Copilot response also blocks that sensitive text from being used in internal or external web searches. One control, three protections. Microsoft documents this as a built-in behavior of the Copilot prompt location, not a separate add-on policy."

**Q: "Are uploaded files in prompts scanned by Copilot DLP prompt controls?"**
> "Not for prompt SIT scanning. Prompt controls evaluate text typed directly in the prompt. Uploaded file contents aren't scanned by that control, so we rely on label-based controls and existing access protections for file content."

**Q: "What licenses do we need?"**
> "Microsoft 365 E5 or E5 Compliance for Purview DLP. Copilot for Microsoft 365 for the Copilot license. Both are required."

**Q: "Does this cover agents — like the prebuilt Copilot agents or ones we build in Copilot Studio?"**
> "The Microsoft 365 Copilot and Copilot Chat location covers prebuilt agents available in M365 Copilot and Copilot Chat — those run under the same DLP enforcement you're seeing today. Custom Copilot Studio agents and declarative agents have their own controls under Dataverse data policies and agent-specific settings, which DSPM for AI and Purview's agent governance layer extend to. The model is the same — sensitivity labels travel, SITs are honored — but the control surface changes per agent type."

**Q: "Can we scope DLP to specific users or departments?"**
> "Yes. DLP policies support group-based scoping. You could enable Copilot DLP for Finance first, then roll out to the full organization."

---

## Natural Follow-Ups

1. **Insider Risk — Risky AI Usage** — already deployed as part of this lab profile. Users who repeatedly trigger Copilot DLP guardrails get scored as higher risk and surface to investigators automatically. Great second-half of the demo for risk-adaptive security teams.
   - **Wizard-step defaults to call out** (matches how most customers configure in the portal): scope is **All users and groups** (no priority-user scoping); **Content to prioritize** = one random sensitivity label + one SIT + one trainable classifier (skip SharePoint sites); **Detection options** = select all indicators and triggering events the template exposes.
2. **DSPM for AI Risk Assessments** — oversharing discovery and remediation. Shows where sensitive data still lives that Copilot could touch. Runbook has activation steps.
3. **Endpoint DLP for Copilot** — paste/upload scenarios on managed devices
4. **Security Copilot for DLP triage** — AI-on-AI investigation story
5. **Shadow AI Prevention Demo** — complementary lab covering external AI tools (separate lab profile)

---

## Demo Environment Quick Reference

| Component | Count | Examples |
|---|---|---|
| Test users | 3 | Megan Torres (Finance), Jordan Kim (Marketing), Nadia Shah (Compliance) |
| Security groups | 2 | Copilot-Users, Compliance-Admins |
| DLP policies | 2 | Copilot Prompt SIT Block (3 rules), Copilot Labeled Content Block (2 rules) |
| Sensitivity labels | 2 parents + 5 sublabels | Confidential (General, Business Sensitive), Highly Confidential (All Employees, Restricted, Regulated Data) |
| Auto-label policies | 1 | SSN → Highly Confidential\Regulated Data |
| Retention | 1 | Copilot interaction retention (365 days) |
| eDiscovery | 1 case | Copilot DLP incident investigation |
| Audit searches | 3 | CopilotInteraction, DlpRuleMatch, DlpRuleUndo |
| Test emails | 4 | SSN, credit card, Copilot interaction context |
| Test documents | 3 | Financial forecast, employee benefits (SSN), patient intake (PHI) |
| Config | `configs/commercial/copilot-dlp-demo.json` | Prefix: `PVCopilotDLP` |
