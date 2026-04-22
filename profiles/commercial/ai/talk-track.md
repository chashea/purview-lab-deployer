# Integrated AI Security Lab — Customer Talk Track

## Overview

**Duration:** 45-75 minutes hands-on (or 30 minutes narrative-only).
**Audience:** CISO + Security Architect + Compliance Director together — any audience that needs the full Microsoft AI security picture.
**Goal:** Show how Purview + Copilot DLP + Shadow AI prevention + Sentinel SIEM work together as one integrated system — not four separate tools.

**Exec tagline:** "Four surfaces, one policy model, one SIEM pane. This is what a complete AI security posture looks like."

---

## When to use this lab vs. focused labs

- **Use this lab** when the customer wants to see the full picture — especially when CISO, SecOps lead, and compliance director are in the same room.
- **Use focused labs** (`copilot-protection`, `shadow-ai`, `purview-sentinel`) when the audience is a single persona or the time budget is tight (15-30 min).

---

## Opening (3 min)

> "There are three AI security stories every enterprise is working on right now. They usually get treated as separate projects with separate tools:
>
> 1. **Protect sanctioned AI** — Microsoft 365 Copilot. Make sure it doesn't leak internal data or process sensitive files it shouldn't.
> 2. **Prevent unsanctioned AI** — ChatGPT, Claude, Gemini. Stop users pasting company data into public AI sites.
> 3. **SIEM visibility** — get those signals in front of the SOC, correlate them with the rest of the security story, drive incident response.
>
> The reality is those three stories are one story. Signals from one surface feed the others. A user who gets blocked pasting customer SSNs into ChatGPT also probably gets flagged by Copilot's prompt DLP. That same user's risk score rises in Insider Risk Management — which *automatically tightens* the DLP enforcement the next time they try.
>
> This lab deploys all three surfaces under one prefix with the signals actually wired together. Let me show you the integrated loop."

---

## Act 1: Discovery — "What's happening today?" (5 min)

**Portal:** Microsoft Purview → Audit → Search

> "Baseline question: what AI activity is already happening in your tenant?"

**Show three pre-configured audit searches:**
1. **Copilot-Interaction-Audit** — every Copilot use
2. **AI-DLP-Match-Audit** — every DLP rule match across all surfaces
3. **AI-Policy-Override-Audit** — attempts to override DLP blocks

**Portal:** Sentinel workspace → workbook `PVAISec-AI Risk Signals`

> "Once you've deployed this lab and signals are flowing, the workbook gives you the aggregated view: Copilot DLP blocks over time, Shadow AI paste attempts by target site (ChatGPT vs. Claude vs. Gemini), Risky AI Usage IRM alerts, and the key panel — **cross-signal users**, the users who have both Copilot DLP blocks AND IRM AI scoring. Those are your real AI-risk humans."

**Optional:** If DSPM for AI is activated, pivot to `DSPM for AI → Reports → Sensitive interactions per generative AI app` for the Microsoft-recommended posture view.

**Transition:** "Now let me show you the enforcement surfaces, starting with sanctioned AI."

---

## Act 2: Copilot DLP — "Sanctioned AI with guardrails" (10 min)

**Portal:** Purview → DLP → Policies → `PVAISec-Copilot Prompt SIT Block` and `PVAISec-Copilot Labeled Content Block`

> "Microsoft 365 Copilot is the sanctioned tool. It runs inside your compliance boundary. But sanctioned doesn't mean unguarded."

**Show the two Copilot DLP policies:**

### PVAISec-Copilot Prompt SIT Block (public preview)
- Location: Microsoft 365 Copilot and Copilot Chat (`CopilotExperiences`)
- Condition: `Content contains sensitive info types` (SSN, Credit Card, PHI)
- Action: `Prevent Copilot from processing content` → blocks the response AND blocks that sensitive text from reaching internal or web searches

> "One policy, three protections: no Copilot response, no internal search, no web search. The sensitive string never leaves the guardrail."

### PVAISec-Copilot Labeled Content Block (GA)
- Location: CopilotExperiences
- Condition: `Content contains sensitivity label = AI Blocked from External Tools` or `AI Regulated Data`
- Action: Prevent Copilot from processing labeled content → files auto-labeled on SSN detection immediately become invisible to Copilot

**Live demo:**

| Prompt | Expected |
|---|---|
| "Summarize benefits for 078-05-1120" | Blocked — SSN in prompt |
| "Summarize the Q4 Financial Forecast document" | Blocked — file is labeled Highly Confidential → AI Blocked |
| "What meetings do I have this week?" | Normal response — no sensitive data, no labeled files |

> "The user gets a policy-driven message. Not a vague error. They know exactly why."

**Transition:** "So Copilot is guarded. What about ChatGPT, Claude, Gemini?"

---

## Act 3: Shadow AI — "Unsanctioned AI prevention" (12 min)

**Portal:** Purview → DLP → Policies → three Shadow AI policies

> "The risk isn't just inside Copilot. Your users are pasting data into public AI sites every day. We protect at three layers."

### Layer 1 — Devices (Endpoint DLP)

**Show:** `PVAISec-Shadow AI - Endpoint Protection`
- Location: Devices
- Block list: 10 AI sites (ChatGPT, Claude, Gemini, Perplexity, Poe, HuggingFace, DeepSeek, etc.)
- Enforcement: tiered by Insider Risk score

**Live demo on managed device:** paste SSN into ChatGPT.com → Endpoint DLP intercepts at paste time, shows policy tip "Use Copilot instead."

### Layer 2 — Browser (Edge for Business)

**Show:** `PVAISec-Shadow AI - Browser Prompt Protection`
- Inline inspection of prompt text in Edge for Business
- Covers consumer AI sites (Copilot consumer, ChatGPT consumer, Gemini, DeepSeek)

**Live demo:** type SSN into Copilot consumer's prompt in Edge → text blocked before submission.

### Layer 3 — Network (SASE/SSE)

**Show:** `PVAISec-Shadow AI - Network AI Traffic`
- Network-layer DLP via SASE/SSE integration
- Covers non-Edge browsers, non-browser apps, APIs

**Key message:**

> "Three layers, same policy logic. Device-level catches paste. Browser-level catches prompt submission. Network-level catches anything that routes around the browser. Together they close the unsanctioned AI gap."

### The asymmetry — Copilot vs. external AI

> "Notice Copilot gets DLP too — but the friction is lower. Same sensitive data, same detection. But Copilot runs inside your compliance boundary, so when DLP catches something, the user gets guided to the sanctioned path. External AI gets hard blocks. That asymmetry is what steers behavior."

---

## Act 4: Insider Risk — "The adaptive bridge" (5 min)

**Portal:** Purview → Insider Risk Management → Policies

> "Here's where the system gets adaptive. The DLP policies you just saw aren't one-size-fits-all. They're tiered by the user's real-time Insider Risk score."

**Show the 3 IRM policies:**
- PVAISec-Risky AI Usage Watch (detects Copilot prompt injection, protected material access)
- PVAISec-AI Data Exfiltration Watch (correlates DLP matches with data-leak signals)
- PVAISec-Departing User AI Risk (elevates risk for departing users who touch AI)

**Wizard-step choices to call out (each policy uses the same defaults — matches what most customers do in the portal):**
- **Users and groups:** All users and groups in your organization (no priority-user scoping — keeps the demo simple and matches the default)
- **Content to prioritize:** one randomly-selected sensitivity label + one SIT + one trainable classifier (skip SharePoint sites — content-specific and brittle across tenants)
- **Detection options:** all indicators and triggering events the template exposes are selected — maximizes the risk surface the demo can show

**Show the tier pattern in `Shadow AI - Endpoint Protection`:**

| User Risk Level | DLP Rule | Enforcement |
|---|---|---|
| Elevated | Endpoint AI Block - Elevated Risk | Hard block |
| Moderate | Endpoint AI Warn - Moderate Risk | Allow with justification |
| Minor | Endpoint AI Audit - Minor Risk | Audit only |

> "Same user, same sensitive data, same AI site — enforcement differs by who they are right now. A consistent engineer who pastes a customer ID once gets audited. Someone who's been flagged for repeated AI-surface violations gets blocked outright. A departing employee? Blocked, no questions.
>
> The IRM score escalates from single events. DLP responds in real time. No admin intervention. That's adaptive security."

---

## Act 5: Sentinel — "One pane, correlated signals" (15 min)

**Portal:** Microsoft Defender portal → Microsoft Sentinel (or Azure portal → Sentinel)

> "Everything we've shown so far lives in Purview. But your SOC doesn't log into Purview — they log into Sentinel. So we stream every signal into a unified SIEM."

### Three connectors

- **Microsoft Defender XDR** (`MicrosoftThreatProtection`): DLP alerts via the XDR pipeline
- **Microsoft 365 Insider Risk Management** (`OfficeIRM`): high-severity IRM alerts
- **Office 365** (`Office365`): unified audit activity (sensitivity label changes, file access, Copilot interactions)

> "Three connectors, full Purview signal coverage in the SIEM."

### Seven analytics rules, including three AI-specific

1. **PVAISec-HighSevDLP** — high-severity DLP alerts
2. **PVAISec-IRMHighSev** — Insider Risk escalations
3. **PVAISec-LabelDowngrade** — pre-exfiltration label stripping (classic insider pattern)
4. **PVAISec-MassDownloadAfterDLP** — cross-table: DLP match + mass download within 4h
5. **PVAISec-CopilotDLPPromptBlock** — AI-specific: every Copilot DLP block becomes an incident
6. **PVAISec-ShadowAIPasteUpload** — AI-specific: paste/upload to ChatGPT/Claude/Gemini
7. **PVAISec-RiskyAIUsageCorrel** — the key rule: users with BOTH Risky AI IRM alerts AND DLP blocks on AI surfaces in the last 4 hours. Two soft signals become a hard incident.

### The IRM auto-triage playbook

**Show:** `PVAISec-IRM-AutoTriage` Logic App

> "When an IRM high-severity incident fires, this Logic App auto-enriches the Sentinel incident with a triage comment. Managed identity, no stored credentials. Sentinel first-party app gets Logic App Contributor on the resource group. Incident-to-comment in under a second."

### Two workbooks

- **PVAISec-Purview Signals** — DLP volume, IRM severity, label activity, top users
- **PVAISec-AI Risk Signals** — Copilot DLP blocks, Shadow AI by target site, Risky AI IRM, cross-signal users, Copilot interaction volume

### The Defender portal unified experience

> "Microsoft Sentinel is GA in the Defender portal. New customers after July 2025 auto-onboard. The Azure portal retires March 2027. For this lab, the workspace works in both — but the Defender portal is where the unified SecOps story lives: SIEM + XDR + identity + endpoint + now Purview AI signals. All one pane, one KQL surface."

---

## Act 6: The integrated loop (3 min)

**This is the money shot. Walk through the full cycle:**

> "Let me close with the loop that makes this integrated:
>
> 1. Rachel tries to paste a customer SSN into ChatGPT. **Endpoint DLP blocks** it.
> 2. That block generates a `SecurityAlert`. The `PVAISec-ShadowAIPasteUpload` Sentinel rule creates an incident. The SOC sees it.
> 3. Rachel also has been running Risky AI prompts in Copilot Chat this week. **Copilot prompt SIT DLP** has blocked three. Her IRM score has crept up.
> 4. **Insider Risk Management** now has Rachel tagged 'Elevated'.
> 5. The *next* time Rachel pastes sensitive data to any AI surface, the DLP enforcement tier **tightens automatically** — no admin action needed. She gets hard-blocked where she used to just get a warning.
> 6. The `PVAISec-RiskyAIUsageCorrel` Sentinel rule notices she has both IRM alerts and DLP AI blocks in the same 4-hour window. **Cross-table incident fires.** The auto-triage playbook enriches it. The SOC sees a single incident that says 'user combining IRM signals and DLP signals on AI surfaces' — and that's the investigation-worthy one.
>
> That loop closes entirely inside Microsoft tooling, with one config file of deploy, and shows up in one SIEM pane."

---

## Closing (2 min)

> "To recap:
>
> 1. **Sanctioned AI** (Copilot) — DLP at the prompt level + label level, preview and GA controls respectively
> 2. **Unsanctioned AI** (ChatGPT et al) — three layers: device, browser, network
> 3. **Insider Risk** — the adaptive bridge that makes DLP policies respond to user behavior
> 4. **Sentinel** — unified SIEM pane, 7 analytics rules, auto-triage playbook, cross-signal correlation
> 5. **The loop** — signals reinforce each other automatically, no admin intervention
>
> This entire environment was deployed programmatically in 20-25 minutes from one config file. It's config-driven, repeatable, tears down cleanly. It's also composable — you can peel off any one lab profile (copilot-protection, shadow-ai, purview-sentinel) for focused audiences.
>
> That's the Microsoft integrated AI security model. Not four tools. One system."

---

## Anticipated Questions

**Q: "Why is this a separate lab from the three focused ones?"**
> "Different use cases. The focused labs ship a tight 15-30 min demo aimed at a single persona. This integrated lab is 45-75 min, shows the signal correlation, and is what you run when CISO + SecOps + compliance are in the same room. All four profiles share the same underlying modules — this one just combines their outputs under one prefix with the Sentinel analytics rules that correlate across surfaces."

**Q: "What licenses do we need?"**
> "Microsoft 365 E5 (or E5 Compliance) for the Purview stack. Microsoft 365 Copilot licenses for Copilot demos. Azure subscription + Log Analytics + Sentinel SKU for the SIEM integration. Defender for Endpoint for the Shadow AI device-layer demos. Most enterprise customers already have all of these — this is about wiring them together."

**Q: "How long until we see cross-signal correlations fire?"**
> "First-run timeline: Copilot DLP and Shadow AI DLP blocks within 4h of deploy. Defender XDR SecurityAlert rows start flowing within 30-60 min of connector consent. IRM alerts within 60-90 min of SIEM export enablement. Cross-signal rules like RiskyAIUsageCorrel need both sides flowing — budget 2-4h from fresh deploy to first integrated incident."

**Q: "Can we demo the adaptive tier escalation live?"**
> "Yes, but it takes setup. Generate 5-10 Shadow AI DLP matches from one user, wait 15-60 min for IRM signal aggregation, check IRM → user risk profile. The user's risk should move from Minor to Moderate. Then rerun the same paste attempt — DLP enforcement should tighten. See `scripts/shadow-ai-test-prompts.md` section F for the exact flow."

**Q: "How does this relate to DSPM for AI?"**
> "This lab is the *enforcement* surface. DSPM for AI is the *posture* surface. DSPM for AI shows where oversharing risk lives, which users carry most AI risk, which SharePoint sites need labeling before Copilot touches them. Enforcement + posture is the complete story. The RUNBOOK has DSPM for AI activation as an optional post-deploy step — strong recommendation for customers who want the full Microsoft AI security picture."

**Q: "What about Copilot Studio agents and custom agents?"**
> "The Copilot DLP location covers prebuilt agents in M365 Copilot. Custom agents built in Copilot Studio have their own controls under Dataverse data policies and agent governance. DSPM for AI extends the visibility to those agents. The model is the same across both — sensitivity labels travel, SITs are honored — the control surface changes per agent type."

**Q: "Can we scope the rollout?"**
> "Every policy in the lab supports group-based scoping. Config already uses `PVAISec-Business-Users` / `PVAISec-AI-Governance` / `PVAISec-Privileged-Data-Owners` groups. Production rollout is typically: pilot on one department in simulation mode → enable enforcement → expand. Same config, change `simulationMode: false` and populate group membership."

**Q: "How does the teardown work?"**
> "Two modes. Non-destructive: removes Purview policies and Sentinel child resources, preserves the Azure resource group and workspace for quick redeploy. Destructive: deletes the resource group entirely — but requires all of a manifest, the correct tags, exact name match, and an explicit `-ForceDeleteResourceGroup` flag. Multiple guards prevent accidents. See RUNBOOK section 10."

---

## Natural Follow-Ups

1. **DSPM for AI activation** — posture surface complementing this enforcement surface
2. **Microsoft Purview Content Hub solution** — already opted-in by this lab, but worth calling out explicitly
3. **Security Copilot for Purview + Sentinel** — AI-on-AI triage
4. **Defender portal onboarding** — unified SecOps experience
5. **Extended Shadow AI coverage** — add SASE/SSE provider integration (Zscaler, Netskope, iboss)
6. **Communication Compliance tuning** — tune the review queue thresholds for the customer's volume

---

## Demo Environment Quick Reference

| Component | Count | Details |
|---|---|---|
| Test users | 5 | rtorres, mchen, nbrooks, dokafor, sreeves |
| Security groups | 3 | AI-Governance, Privileged-Data-Owners, Business-Users |
| Sensitivity labels | 2 parents + 10 sublabels | AI-specific taxonomy |
| Auto-label policies | 2 | SSN → Regulated; Financial PII → Confidential Regulated |
| DLP policies | 5 | Copilot Prompt, Copilot Label, Endpoint, Browser, Network |
| DLP rules | 9 | Risk-tiered across all 5 policies |
| IRM policies | 3 | Risky AI, Data leaks, Departing users |
| Comm Compliance | 2 | Activity Collection, PII/PHI Detection |
| Retention | 5 | Exchange/SharePoint/OneDrive + Copilot + Enterprise AI + Other AI |
| eDiscovery | 1 | Unified AI-Security-Incident-Review |
| Conditional Access | 2 | Block high-risk + MFA (report-only) |
| Audit searches | 3 | Copilot, DLP, Override |
| Sentinel analytics rules | 7 | General + 3 AI-specific + cross-signal correlation |
| Sentinel workbooks | 2 | Purview Signals + AI Risk Signals |
| Playbook | 1 | IRM auto-triage Logic App |
| Seed emails | 4 | Cross-reference Copilot + Shadow AI scenarios |
| Seed documents | 5 | Auto-labeled via Graph assignSensitivityLabel |
| Config | `configs/commercial/ai-security-demo.json` | Prefix: `PVAISec` |
