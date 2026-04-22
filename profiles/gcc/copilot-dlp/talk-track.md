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
2. **DLP `Locations` + `EnforcementPlanes` parameters** are available on `New-DlpCompliancePolicy` (run pre-flight from RUNBOOK)
3. **CopilotInteraction audit events** are flowing (run pre-flight from RUNBOOK)

If any feature is not yet available in GCC, use the **"coming to GCC"** callout pattern:

> "This capability is generally available in commercial tenants today, and rolling out to GCC. The policy configuration is identical — when the feature arrives in your GCC tenant, it will enforce immediately."

This positions the demo as forward-looking without losing credibility.

### GCC Limitation: No SIT-Based Copilot DLP

> **Important:** In GCC, you cannot create a DLP policy targeting Microsoft 365 Copilot with Sensitive Information Type (SIT) conditions in the rules. Only label-based rules are supported for Copilot DLP in GCC. SIT-based Copilot DLP (blocking prompts containing SSN, credit card, PHI, etc.) is available in commercial tenants but not in GCC. This lab focuses exclusively on label-based content blocking.

---

## Opening (2 min)

> "Copilot doesn't invent risk. It amplifies existing data exposure.
>
> In this lab, we'll let Copilot loose — then show how Purview puts it back inside the guardrails without breaking productivity.
>
> By the end of this session, you'll see how to:
> - Prevent Copilot from summarizing or reasoning over labeled content
> - See the full audit trail when Copilot is constrained
>
> The core governance model is the same in GCC, but there are feature differences to call out clearly: GCC currently supports label-based Copilot DLP, while SIT-based Copilot prompt blocking remains commercial-only.
>
> **Note:** In GCC, Copilot DLP supports label-based content blocking. SIT-based prompt blocking (detecting PII/PHI/PCI in prompts) is not available for Copilot in GCC — that capability is commercial-only today."

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

## Phase 1: Block Labeled Files — "The label is the boundary" (10 min)

**Portal:** Microsoft Purview > DLP > Policies > `PVCopilotDLP-Copilot Labeled Content Block`

> "The first guardrail: if a file has a sensitivity label that restricts AI access, Copilot cannot summarize, reference, or reason over it."

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

> "Important technical note: in GCC, Copilot DLP only supports label-based conditions. SIT-based conditions (detecting sensitive info types in prompts) are not available for Copilot DLP rules in GCC. This lab uses a single policy with two label-based rules — one for Restricted content, one for Regulated Data."

---

## Phase 2: Evidence & Investigations — "Prove it works" (5 min)

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
> 2. **Guardrail #1** — DLP blocks Copilot from labeled content (Highly Confidential)
> 3. **Full audit trail** — every blocked event is recorded and investigable
>
> We didn't turn Copilot off. We taught it what it's allowed to see, summarize, and search.
>
> In GCC, label-based content blocking is the primary Copilot DLP control. SIT-based prompt blocking is available in commercial — when it comes to GCC, the same policy model will apply.
>
> This runs with GCC-appropriate guardrails today: label-based DLP enforcement, sensitivity labels, and audit evidence. As GCC feature rollout expands, the same control model extends without redesign. G5 licensing, GCC compliance boundary, defensible governance."

---

## Anticipated Questions

**Q: "Is this the same in GCC as commercial?"**
> "The label-based DLP enforcement, sensitivity labels, and audit infrastructure are the same. The key differences in GCC: SIT-based Copilot prompt DLP — which is public preview on commercial and also blocks the sensitive prompt text from reaching web search — isn't available in GCC yet. When it rolls out, the same policy model applies. Feature rollout in GCC typically lags commercial by weeks to months."

**Q: "Does this work with GCC High or DoD?"**
> "This demo targets GCC (not GCC High or DoD). GCC High and DoD have different endpoint configurations and more restrictive feature availability. Contact your Microsoft account team for GCC High/DoD guidance."

**Q: "Can we map this to CUI categories?"**
> "Absolutely. The sensitivity labels can be named and configured to match your agency's CUI taxonomy. 'Highly Confidential > Restricted' could be 'CUI > Specified' with the same enforcement behavior."

**Q: "Does this actually block Copilot, or just log it?"**
> "Both. The DLP action is 'block' — Copilot cannot return a response. And every block generates an audit record. In simulation mode, it logs without blocking, which is useful for policy tuning."

**Q: "Are uploaded files in prompts scanned by Copilot DLP prompt controls?"**
> "Prompt SIT scanning evaluates text typed directly in prompts. Uploaded file contents aren't scanned by that control. In GCC, our lab relies on label-based protections and access controls for file content boundaries."

**Q: "What if Copilot features aren't available in our GCC tenant yet?"**
> "The deployer degrades gracefully — it creates the policies without the Copilot location and logs a warning. When the feature rolls out to your tenant, you add the location and enforcement begins immediately. No policy rewrite needed."

**Q: "Does this cover prebuilt agents running inside Copilot?"**
> "Yes. The Microsoft 365 Copilot and Copilot Chat location per Microsoft's documentation extends the same DLP enforcement to prebuilt agents available inside M365 Copilot. In GCC, agent availability tracks the underlying Copilot rollout — when the agents show up, they inherit these same guardrails."

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
| DLP policies | 1 | Copilot Labeled Content Block (2 rules) |
| Sensitivity labels | 2 parents + 5 sublabels | Confidential (General, Business Sensitive), Highly Confidential (All Employees, Restricted, Regulated Data) |
| Auto-label policies | 1 | SSN → Highly Confidential\Regulated Data |
| Retention | 1 | Copilot interaction retention (365 days) |
| eDiscovery | 1 case | Copilot DLP incident investigation |
| Audit searches | 3 | CopilotInteraction, DlpRuleMatch, DlpRuleUndo |
| Test emails | 4 | SSN, credit card, Copilot interaction context |
| Test documents | 3 | Financial forecast, employee benefits (SSN), patient intake (PHI) |
| Config | `configs/gcc/copilot-dlp-demo.json` | Prefix: `PVCopilotDLP` |
| License | Microsoft 365 G5 + Copilot for M365 | GCC |
