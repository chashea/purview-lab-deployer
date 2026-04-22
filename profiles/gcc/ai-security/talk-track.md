# Integrated AI Security Lab — Customer Talk Track (GCC)

GCC variant. See the [commercial talk-track](../../commercial/ai-security/talk-track.md) for the full 7-act narrative. This document captures GCC-specific framing and substitutions.

## Overview

**Duration:** 45-75 minutes hands-on.
**Audience:** Government CISO, SecOps lead, agency compliance director — anyone who needs the integrated Microsoft AI security picture for a GCC environment.
**Goal:** Same integrated 4-in-1 story as commercial, adapted for Azure Government constraints.

**Exec tagline:** "Same integrated Microsoft AI security model as commercial, running inside the GCC compliance boundary. FedRAMP-authorized SIEM. Compliance-aware Copilot. No data leaving the boundary."

## GCC-specific framing

The commercial 7-act structure applies directly. The **Purview-for-Copilot GCC wave (April 2025)** and **M365 Copilot for GCC GA (December 2024)** closed the biggest parity gaps. Remaining deltas:

| Commercial framing | GCC framing |
|---|---|
| `portal.azure.com` | `portal.azure.us` |
| Region `eastus` | `usgovvirginia` / `usgovarizona` |
| Defender portal unified SecOps (GA, auto-onboard July 2025) | Separate GCC rollout — validate per tenant; Azure portal Sentinel fully supported |
| Sentinel data lake (GA July 2025) | Rollout pending in GCC |
| Microsoft 365 Copilot licenses | Microsoft 365 Copilot for GCC licenses |
| "E5" | "G5" (GCC) |
| Copilot prompt SIT DLP (public preview) | Preview on commercial; GCC rollout lag expected |
| Browser Data Security inline block | Not explicitly in GCC service-description tables — verify |
| Network Data Security SASE/SSE | Not explicitly in GCC service-description tables — verify |

## Act substitutions

### Act 2 — Copilot DLP in GCC

The two Copilot DLP policies (prompt SIT block + label block) deploy identically. Call out on slide: prompt SIT is public preview in commercial; validate tenant availability in GCC before relying on it for a live block demo. Label-based Copilot DLP is GA — safe to demo unconditionally.

### Act 5 — Sentinel in GCC

Sentinel is GA in GCC (Azure portal experience). The Defender portal Sentinel experience rolls out separately per GCC tenant — if it's available, use it; if not, demo in the Azure portal.

All 7 analytics rules deploy identically. The `PVAISec-RiskyAIUsageCorrel` cross-signal rule still correlates across the same `SecurityAlert` / `OfficeActivity` tables.

### Act 6 — The integrated loop in GCC

The same 6-step adaptive loop applies. One caveat: IRM feature rollout in GCC can lag commercial, so if Risky AI Usage IRM alerts aren't flowing in your tenant, the cross-signal correlation rule has fewer data points to match on. Readiness script catches this.

## Anticipated GCC-specific questions

**Q: "Is this FedRAMP-authorized?"**
> "The Azure Government Sentinel workspace inherits FedRAMP High authorization. Microsoft 365 G5 inherits FedRAMP High for the covered services. Purview workloads running on G5 are within scope. For specific control mapping, pair this lab with a Compliance Manager assessment using the FedRAMP High regulatory template."

**Q: "GCC vs. GCC High vs. DoD?"**
> "This lab targets GCC (Moderate). GCC High and DoD have more restricted feature rollouts and some APIs explicitly don't work — for example, Graph `assignSensitivityLabel` is unavailable in L4/L5. For GCC High or DoD, validate each capability against Azure Government service descriptions before deploying."

**Q: "Does the cross-signal correlation still fire in GCC?"**
> "Yes, the `PVAISec-RiskyAIUsageCorrel` rule works identically — it queries `SecurityAlert` rows from the IRM and DLP pipelines and joins them. The only GCC-specific concern: IRM feature rollout timing affects how soon those alerts start flowing. Once both sides are populated, correlation fires on schedule."

**Q: "Can we use the Defender portal?"**
> "Sentinel in the Defender portal rolls out to GCC on a separate schedule from commercial. Validate in your tenant — if it's available, use it for the unified SecOps experience. If not, the Azure portal works identically; the lab's artifacts are portable. Microsoft has committed to bringing the Defender portal experience to GCC; timeline varies by tenant."

**Q: "Does DSPM for AI work in GCC?"**
> "Yes, DSPM for AI is available in GCC Moderate per MS Learn service descriptions (Create policies and view analytics for AI apps = Available). The single GCC-H/DoD caveat — 'Browse to URL policy cannot be created; only supported AI sites' — doesn't apply to regular GCC. Activation flows identically to commercial (see commercial RUNBOOK section 7)."

**Q: "Do all 11 workloads in the ai-security lab deploy in GCC?"**
> "Based on MS Learn service-description tables, yes for 9 of them confirmed Available (testUsers, sensitivityLabels, retention incl. AI-Applications, eDiscovery, communicationCompliance, insiderRisk, conditionalAccess, auditConfig, sentinelIntegration). For dlp, the Copilot label-block policy is in the April 2025 Purview-for-Copilot wave so should work; Copilot prompt SIT and Browser/Network Data Security are the real gaps to validate per-tenant. The readiness scripts catch exactly this."

## What stays identical

- All 5 DLP policies (deploy regardless of feature availability; enforcement degrades gracefully)
- All 3 IRM policies (deploy regardless; availability depends on GCC rollout)
- All 7 Sentinel analytics rules
- Both workbooks (Purview Signals, AI Risk Signals)
- The IRM auto-triage playbook
- Teardown safety gates
- The 6-step integrated loop narrative

The whole lab is a superset; GCC caveats are about which parts of it are actively enforcing vs. audit-only given your tenant's current feature stage.
