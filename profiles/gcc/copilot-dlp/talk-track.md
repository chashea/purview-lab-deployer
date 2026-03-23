# Copilot DLP Guardrails — Customer Talk Track (GCC)

## Overview

**Duration:** 20–30 minutes (expandable to 90–120 with hands-on)
**Audience:** CISO, Security/Compliance leadership, IT decision-makers in government organizations
**Goal:** Show how Purview DLP enforces data boundaries for M365 Copilot in GCC — and what actually happens when those guardrails trigger.
**License:** Microsoft 365 G5 (or G5 Compliance add-on) + Copilot for Microsoft 365

**Exec tagline:** "We're not turning Copilot off — we're teaching it what it's allowed to see, summarize, and search."

---

## GCC Presenter Notes

Before delivering this talk track in a GCC environment, confirm:

1. **Copilot is available and licensed** in the GCC tenant
2. **DLP CopilotLocation parameter** is available (run pre-flight from RUNBOOK)
3. **CopilotInteraction audit events** are flowing (run pre-flight from RUNBOOK)

If any feature is not yet available in GCC, use the **"coming to GCC"** callout pattern:

> "This capability is generally available in commercial tenants today, and rolling out to GCC. The policy configuration is identical — when the feature arrives in your GCC tenant, it will enforce immediately."

This positions the demo as forward-looking without losing credibility.

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
> All of this runs the same in GCC as commercial. Same policies, same enforcement model, same audit trail. The only difference is the licensing — G5 instead of E5."

---

## Phase 0: Baseline — "The before state" (5 min)

**Portal:** Microsoft 365 Copilot

> "Before we turn on any guardrails, let's see what Copilot can do with full access."

**Show:**
1. Copilot summarizing a document from SharePoint
2. Copilot answering a question based on file content
3. Copilot providing a web-backed response

> "Everything works. Copilot has access to your files, your emails, your data. That's the value proposition — but for government data, the risk profile is different. Now let's add the guardrails."

**Transition:** "The question every government CISO asks: How do we trust Copilot with our data?"

---

## Phase 1: Block Sensitive Prompts — "What you type matters" (10 min)

**Portal:** Microsoft Purview > DLP > Policies > `PVCopilotDLP-Copilot Prompt SIT Block`

> "The first guardrail: if a user types sensitive information directly into a Copilot prompt, DLP intercepts it."

**Show the policy:**
- Location: Microsoft 365 Copilot & Copilot Chat
- Condition: Content contains sensitive info types
- 3 rules: SSN, Credit Card, PHI
- Action: Block Copilot response

**Live demo:**

| Prompt | Result |
|---|---|
| "Summarize benefits for employee 078-05-1120" | Blocked — SSN detected |
| "What charges on card 4532-8721-0034-6619?" | Blocked — credit card detected |
| "Summarize treatment for diabetes mellitus" | Blocked — PHI detected |
| "What are our Q4 revenue projections?" | Normal response — no sensitive data |

> "The user sees a clear, policy-driven message — not a vague error. They know exactly why Copilot can't answer, and they know it's intentional."

> *GCC callout:* "This enforcement uses the same SIT detection engine across commercial and GCC. The patterns, checksums, and confidence levels are identical."

---

## Phase 2: Block Labeled Files — "The label is the boundary" (10 min)

**Portal:** Microsoft Purview > DLP > Policies > `PVCopilotDLP-Copilot Labeled Content Block`

> "The second guardrail: if a file has a sensitivity label that restricts AI access, Copilot cannot summarize, reference, or reason over it."

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

> "For government organizations, this is critical. CUI, FOUO, and agency-specific classifications can map directly to sensitivity labels. The label travels with the document — across SharePoint, OneDrive, Exchange, and now Copilot."

### Expert Callout

> "Important technical note: you cannot mix sensitive info type conditions and label conditions in the same DLP rule. But you can use multiple rules in one policy, or separate policies — which is exactly what we've done here."

---

## Phase 3: Web Search Prevention — "Even the web has boundaries" (5 min)

> "This capability is currently in Private Preview. For government organizations, this is especially relevant — you don't want Copilot sending CUI-adjacent prompts to web search endpoints."

**Explain the control:**
- Inline DLP prevents Copilot from using sensitive data for external web search queries
- Even if Copilot could answer the question, Purview decides it shouldn't
- The prompt itself would carry sensitive data outside the compliance boundary

> "Even if Copilot could answer the question, Purview decides it shouldn't. The sensitive data stays inside the boundary. This is the same model whether you're commercial or GCC."

---

## Phase 4: Evidence & Investigations — "Prove it works" (5 min)

**Portal:** Microsoft Purview > Audit > Search

> "Every time Copilot is constrained by DLP, the event is recorded. For government organizations, this audit trail is essential for FISMA, FedRAMP, and agency-specific compliance requirements."

**Show:**
1. **DlpRuleMatch audit** — every Copilot prompt or file access blocked by DLP
2. **CopilotInteraction audit** — all Copilot usage (if available in GCC)
3. **DLP alert dashboard** — policy violations with Copilot context

**Show eDiscovery case:**

> "If an incident needs investigation, everything is ready. The eDiscovery case has a hold query preserving Copilot-related communications and a search query for sensitive data references."

> "This is defensible AI governance. Not 'we think Copilot is safe' — 'here's the audit trail that proves it.' That's the standard government CISOs expect."

---

## Closing (2 min)

> "To recap — what you've seen today:
>
> 1. **Copilot without guardrails** — full access to everything
> 2. **Guardrail #1** — DLP blocks sensitive data in prompts (SSN, credit card, PHI)
> 3. **Guardrail #2** — DLP blocks Copilot from labeled content (Highly Confidential)
> 4. **Guardrail #3** — DLP prevents sensitive data in web search (preview)
> 5. **Full audit trail** — every blocked event is recorded and investigable
>
> We didn't turn Copilot off. We taught it what it's allowed to see, summarize, and search.
>
> This runs identically in GCC. Same policies, same enforcement, same audit trail. G5 licensing, GCC compliance boundary. Your agency's data stays inside the guardrails."

---

## Anticipated Questions

**Q: "Is this the same in GCC as commercial?"**
> "Yes. The DLP engine, sensitivity labels, and audit infrastructure are the same. The only differences are licensing (G5 vs E5) and feature rollout timing — GCC may lag commercial by weeks to months on new features."

**Q: "Does this work with GCC High or DoD?"**
> "This demo targets GCC (not GCC High or DoD). GCC High and DoD have different endpoint configurations and more restrictive feature availability. Contact your Microsoft account team for GCC High/DoD guidance."

**Q: "Can we map this to CUI categories?"**
> "Absolutely. The sensitivity labels can be named and configured to match your agency's CUI taxonomy. 'Highly Confidential > Restricted' could be 'CUI > Specified' with the same enforcement behavior."

**Q: "Does this actually block Copilot, or just log it?"**
> "Both. The DLP action is 'block' — Copilot cannot return a response. And every block generates an audit record. In simulation mode, it logs without blocking, which is useful for policy tuning."

**Q: "What if Copilot features aren't available in our GCC tenant yet?"**
> "The deployer degrades gracefully — it creates the policies without the Copilot location and logs a warning. When the feature rolls out to your tenant, you add the location and enforcement begins immediately. No policy rewrite needed."

**Q: "What licenses do we need?"**
> "Microsoft 365 G5 or G5 Compliance for Purview DLP. Copilot for Microsoft 365 for the Copilot license. Both are required."

**Q: "How does this relate to FedRAMP/FISMA?"**
> "The audit trail provides the evidence chain that FedRAMP and FISMA require for AI governance. Every Copilot interaction constrained by DLP is recorded with policy context, user identity, and timestamp. This maps directly to NIST 800-53 AU controls."

---

## Natural Follow-Ups

1. **DSPM for AI Risk Assessments** — oversharing discovery and remediation
2. **Endpoint DLP for Copilot** — paste/upload scenarios on managed devices
3. **CUI/FOUO label mapping** — agency-specific sensitivity label taxonomy
4. **Shadow AI Prevention Demo** — complementary lab covering external AI tools (separate lab profile)

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
| Config | `configs/gcc/copilot-dlp-demo.json` | Prefix: `PVCopilotDLP` |
| License | Microsoft 365 G5 + Copilot for M365 | GCC |
