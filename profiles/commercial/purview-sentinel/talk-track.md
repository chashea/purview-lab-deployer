# Purview → Sentinel Integration — Customer Talk Track

## Overview

**Duration:** 15–25 minutes
**Audience:** CISO, SOC lead, compliance director, security architect
**Goal:** Show how Purview compliance signals become actionable SIEM investigations when streamed into Sentinel — and how the Defender portal unifies the SIEM + XDR + AI signal story.

**Exec tagline:** "Compliance signals aren't just for the compliance team. When a DLP match or an insider-risk score flows into your SIEM, it becomes a threat signal your SOC can act on."

---

## Opening (2 min)

> "Most customers run Purview and Sentinel in separate teams, separate dashboards, separate response workflows. The problem: DLP alerts and insider-risk scores are early indicators of the exact incidents your SOC cares about — data exfiltration, insider theft, compromised account behavior. Keeping those signals locked inside the compliance team means your SOC sees the breach too late.
>
> What we deployed here closes that gap. Purview signals stream into Sentinel. Analytics rules correlate them with Defender XDR. A Logic App playbook auto-triages high-severity IRM incidents. All of it renders in either the Azure portal or the Defender portal — Microsoft's unified SecOps experience."

---

## Act 1: The unified portal story (3 min)

**Portal:** [security.microsoft.com](https://security.microsoft.com) (Defender portal)

> "Microsoft's direction for Sentinel is clear: by March 2027, the Azure portal retires and everything lives in the Defender portal. New customers onboarded after July 2025 auto-land here. The benefit is concrete — one pane for SIEM, XDR, identity, endpoint, cloud apps, and now Purview."

**Show the unified nav:**
- **Microsoft Sentinel** node alongside Microsoft Defender for Endpoint, Identity, Cloud Apps, Office 365
- **Advanced hunting** query surface covering both Sentinel tables (`SecurityAlert`, `OfficeActivity`, `PurviewDataSensitivityLogs`) and Defender tables (`IdentityLogonEvents`, `DeviceEvents`, `EmailEvents`)
- **Microsoft Sentinel data lake** — cost-optimized long-term storage tier (GA July 2025)

> "Your compliance data, your endpoint data, your identity data — one KQL query surface."

**Transition:** "Let me show you the Purview side flowing in."

---

## Act 2: Connectors — "The compliance signal fire hose" (4 min)

**Portal:** Sentinel → **Data connectors** (or Defender portal → Sentinel → Configurations → Data connectors)

**Show three connected connectors:**

### Microsoft Defender XDR
- ARM kind: `MicrosoftThreatProtection`
- Streams: incidents + alerts (including DLP alerts flowing through the XDR pipeline)
- Produces: `SecurityAlert`, `AlertInfo`, `AlertEvidence`, plus Defender XDR advanced hunting tables

### Microsoft 365 Insider Risk Management
- ARM kind: `OfficeIRM`
- Streams: IRM high-severity alerts (via Purview SIEM export setting)
- Produces: `SecurityAlert` rows tagged with IRM provider metadata

### Office 365
- ARM kind: `Office365`
- Streams: Exchange, SharePoint, Teams unified audit
- Produces: `OfficeActivity`

> "Between those three, your Sentinel workspace sees the full Purview compliance surface — DLP matches, IRM scores, sensitivity label changes, user activity, sharing events. KQL does the rest."

**Expert callout:**

> "The IRM connector kind is `OfficeIRM` in the ARM schema. Earlier lab versions used `MicrosoftPurviewInformationProtection` — that's a different connector for Information Protection labels. If you've got existing automation that references the wrong kind, it's probably not flowing data. Worth checking."

---

## Act 3: Analytics rules — "Signal to incident" (4 min)

**Portal:** Sentinel → **Analytics**

**Show four active rules with `PVSentinel-` prefix:**

### PVSentinel-HighSevDLP

> "High-severity DLP alerts from Purview come in via Defender XDR, land as `SecurityAlert` rows, and this rule creates Sentinel incidents for each. Entity mapping ties the alert to the user account so the investigator can pivot immediately."

Show rule query:
```kql
SecurityAlert
| where TimeGenerated > ago(1h)
| where ProductName has 'Microsoft Data Loss Prevention' or ProductName has 'Microsoft 365 DLP'
| where AlertSeverity in ('High','Medium')
```

### PVSentinel-IRMHighSev

> "Insider Risk high-severity alerts get the same treatment. The IRM score escalation — minor to moderate to elevated — happens in Purview. Once it crosses the high bar, it's a Sentinel incident."

### PVSentinel-LabelDowngrade

> "Here's the interesting one. Someone relabels a Highly Confidential document as Internal, we catch it via `OfficeActivity` audit. That's a classic pre-exfiltration pattern — strip the protection, then leak. Medium severity by default, but most customers bump it to High once they see their baseline rate."

### PVSentinel-MassDownloadAfterDLP

> "Cross-table correlation: a DLP match in the last hour AND a mass download by the same user in the last four hours. Two signals that are noise on their own, but together are an incident."

---

## Act 4: The IRM auto-triage playbook (3 min)

**Portal:** Sentinel → **Automation** → `PVSentinel-IRM-AutoTriage`

**Show the Logic App:**
- Trigger: Microsoft Sentinel incident (filtered to the IRM analytics rule)
- Action: Append enrichment comment with triage guidance, link back to Purview IRM case, suggest response playbook

**Show the automation rule wiring:**
- Condition: analytic rule = `PVSentinel-IRMHighSev`, severity = High
- Action: Run playbook → `PVSentinel-IRM-AutoTriage`

> "No SOC analyst has to click through to Purview to find out what triggered this. The playbook appends the context automatically. Mean time to first action drops from 'next shift' to 'before the tab loads.'"

**Identity model:**
- Logic App uses a **system-assigned managed identity** — no stored credentials
- Managed identity gets **Microsoft Sentinel Responder** on the workspace
- Sentinel first-party app gets **Logic App Contributor** on the resource group (so Sentinel can invoke the playbook)

> "All that scaffolding is deployed programmatically. One config file, managed identities end-to-end, zero passwords."

---

## Act 5: The workbook — "Executive-ready" (2 min)

**Portal:** Sentinel → **Workbooks** → `PVSentinel-Purview Signals`

**Show panels:**
- DLP alert volume over time
- IRM severity distribution
- Top sensitivity label downgrades by user
- Cross-table: users with both DLP and IRM signals in the same window

> "This is the CISO-level view. When someone asks 'how is our data leaving?' you pivot to this workbook. Not raw logs — answers."

---

## Act 6: Complementary stories (2 min)

> "This lab is one piece of the larger Purview-in-Sentinel story. Three natural extensions:"

### Microsoft Purview Content Hub solution
> "Microsoft ships an official Purview solution in the Content Hub that adds analytics rules for sensitive data discovery and the `PurviewDataSensitivityLogs` table. One-click install, complements this lab's custom rules."

### DSPM for AI + Shadow AI + Copilot labs
> "If you also deployed those labs, all their signals flow here. Copilot prompt blocks, shadow AI paste attempts, DSPM for AI risk scores — same Sentinel workspace, same playbook pattern, same unified portal."

### Microsoft Sentinel data lake
> "New in July 2025. High-volume tables like `OfficeActivity` and `DeviceEvents` can go to the lake tier for long-term cheap retention, while alert tables stay in analytics for real-time rules. Config supports this; RUNBOOK walks through it."

---

## Closing (2 min)

> "To recap:
>
> 1. **Unified portal** — Defender portal is Microsoft's SecOps direction. This lab's artifacts work in both Azure and Defender portals.
> 2. **Three connectors** — Defender XDR, Insider Risk Management, Office 365. Correct ARM kinds per MS Learn.
> 3. **Four analytics rules** — DLP, IRM, label downgrade, cross-table correlation. Full entity mappings.
> 4. **Auto-triage playbook** — managed identity, RBAC scaffolded, incident-to-comment in seconds.
> 5. **Workbook** — executive-ready visualization across all three signal sources.
> 6. **Teardown is safety-gated** — this is the only lab that touches Azure subscription resources; multiple guards prevent accidental destruction.
>
> Compliance signals → SIEM incidents → auto-triage → executive dashboard. All deployed in minutes from one config file. That's the Purview + Sentinel model."

---

## Anticipated Questions

**Q: "Should we migrate to the Defender portal now?"**
> "Yes — Microsoft recommends it for all new deployments, and the Azure portal retires March 31, 2027. The migration is non-disruptive: your workspace, rules, and connectors work identically. Just onboard the workspace and redirect your bookmarks. The unified portal adds Defender XDR advanced hunting, exposure management, and blast-radius analysis on top."

**Q: "Why is the IRM connector kind `OfficeIRM` and not `MicrosoftPurviewInformationProtection`?"**
> "They're different products. `OfficeIRM` is the Microsoft 365 Insider Risk Management connector — produces `SecurityAlert` rows. `MicrosoftPurviewInformationProtection` is the Information Protection connector — produces label activity logs. Getting this wrong is a common integration bug; the lab was updated to use the correct kind per MS Learn."

**Q: "Do IRM alerts need any setup beyond the connector?"**
> "Yes — Purview → Settings → Insider Risk Management → Export alerts must be toggled on. Without it, IRM alerts stay inside Purview and never flow to Sentinel. Allow 60 minutes for the first batch."

**Q: "How is the demo IRM policy scoped?"**
> "This lab's `Sentinel-IRM-Demo` policy uses the defaults most customers apply in the portal: **All users and groups** (no priority-user scoping), **Content to prioritize** = one randomly-selected sensitivity label + one SIT + one trainable classifier (skip SharePoint sites — content-specific and brittle across tenants), **Detection options** = every indicator and triggering event the template exposes. Keeps the signal surface wide so the Sentinel integration has alerts to correlate on day one."

**Q: "What's the data lake tier and should we use it?"**
> "Sentinel data lake is a cost-optimized long-term storage tier launched July 2025. High-volume tables like `OfficeActivity` benefit from split tiering — recent data in analytics for rules, older data in lake for compliance and investigation. Alert tables like `SecurityAlert` should stay in analytics. RUNBOOK section 6 has the recommended split for this lab."

**Q: "What if our Purview tenant is in GCC?"**
> "This lab ships a GCC variant. Same connectors, same analytics rules — but the Defender portal experience in GCC is on a different rollout schedule and Azure Government endpoints replace the commercial ones. See the GCC README for the differences."

**Q: "Can we scope the rules to specific business units?"**
> "Yes. The analytics rule queries use `SecurityAlert` and `OfficeActivity` — both support filtering by UPN, department, or any other user attribute. Add a `| where TargetUserName in (...)` clause. Or use Sentinel's automation rule grouping to route incidents to specific SOC queues."

**Q: "How much does this cost?"**
> "Three cost dimensions: (1) Log Analytics ingestion (~$2.30/GB for the analytics tier), (2) Sentinel SKU on top of Log Analytics, (3) data lake storage (~10-20% of analytics cost). This lab defaults to PerGB2018 at 30-day retention for low-cost demo. Production pricing depends on your ingestion volume — the data lake tier dramatically reduces long-term costs for high-volume tables."

**Q: "What about the Security Copilot for Sentinel integration?"**
> "Security Copilot embeds into both portals and can query Sentinel data in natural language, generate hunting queries, and auto-summarize incidents. Not included in this lab, but it's the natural next step — pair it with this deployment and analyst workflow time drops again."

---

## Natural Follow-Ups

1. **Microsoft Purview Content Hub solution install** — ships MS-maintained analytics rules (`Sensitive Data Discovered in the Last 24 Hours`) and workbook as complement to this lab
2. **Defender portal migration** — recommended for all new Sentinel deployments
3. **DSPM for AI signal ingestion** — if the DSPM for AI lab is deployed, its signals flow into this same workspace
4. **Sentinel data lake tier configuration** — cost optimization for high-volume tables
5. **Security Copilot for Purview + Sentinel** — AI triage on top of this stack

---

## Demo Environment Quick Reference

| Component | Count | Details |
|---|---|---|
| Azure resource group | 1 | `PVSentinel-rg` (eastus by default) |
| Log Analytics workspace | 1 | `PVSentinel-ws` (PerGB2018, 30-day retention) |
| Sentinel onboarding | 1 | Workspace-level |
| Content Hub solutions | 3 | Defender XDR, IRM, Microsoft 365 |
| Data connectors | 3 | `MicrosoftThreatProtection`, `OfficeIRM`, `Office365` |
| Analytics rules | 4 | DLP, IRM, LabelDowngrade, MassDownloadAfterDLP |
| Workbook | 1 | Purview Signals |
| Logic App playbook | 1 | IRM auto-triage |
| Automation rule | 1 | Wires IRM high-sev → playbook |
| Test users | 3 | rtorres, mchen, jblake |
| DLP policy | 1 | Sentinel-DLP-Demo (SSN high severity) |
| IRM policy | 1 | Sentinel-IRM-Demo (Data leaks template) |
| Seed email | 1 | Triggers DLP → Defender XDR → Sentinel flow |
| Config | `configs/commercial/purview-sentinel-demo.json` | Prefix: `PVSentinel` |
