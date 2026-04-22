# Purview → Sentinel Integration — Customer Talk Track (GCC)

GCC variant. See the [commercial talk-track](../../commercial/purview-sentinel/talk-track.md) for the full flow. This document captures GCC-specific framing.

## Overview

**Duration:** 15–25 minutes
**Audience:** Government CISO, SOC lead, compliance director
**Goal:** Show how Purview compliance signals become actionable SIEM investigations in Microsoft Sentinel (GCC) — adapted for government cloud constraints.

**Exec tagline:** "Same unified SecOps model as commercial, deployed on Azure Government. Compliance signals into SIEM, SOC-ready incidents, auto-triage playbooks — all within the GCC compliance boundary."

---

## GCC-specific framing

The commercial 6-act structure (Unified portal → Connectors → Analytics rules → Auto-triage playbook → Workbook → Complementary stories) applies directly. Swap these references when presenting to a GCC audience:

| Commercial framing | GCC framing |
|---|---|
| Microsoft Defender portal | Microsoft Defender portal (availability varies by tenant — check your rollout) |
| `portal.azure.com` | `portal.azure.us` (Azure Government) |
| Region `eastus` | Region `usgovvirginia` or `usgovarizona` |
| Data lake tier (GA July 2025) | Data lake tier (availability pending in GCC — validate) |
| New customer auto-onboarding to Defender portal (July 2025) | GCC rollout on separate schedule — validate per-tenant |

## Anticipated GCC-specific questions

**Q: "Does the Defender portal unified SecOps experience work in GCC?"**
> "Microsoft is rolling it out to GCC on a separate schedule from commercial. Check service descriptions for current availability. The Azure portal Sentinel experience works identically in GCC today, so the lab's artifacts are fully functional regardless."

**Q: "What about GCC High or DoD?"**
> "This lab targets GCC (Moderate). GCC High and DoD tenants have more restricted feature rollouts — validate each connector kind against Azure Government GCC High / DoD service descriptions before deploying."

**Q: "Can we map this to FedRAMP requirements?"**
> "The Sentinel workspace in Azure Government inherits FedRAMP High authorization. The Purview signals you're streaming carry their own compliance boundary. For FedRAMP-specific control mapping, Compliance Manager ships regulatory templates — pair this lab with a Compliance Manager baseline assessment for the full story."

**Q: "Is the IRM connector available in GCC today?"**
> "Microsoft 365 Insider Risk Management in GCC has had rolling feature availability. The `OfficeIRM` Sentinel connector is supported, but the SIEM export toggle in Purview settings depends on your GCC tenant's feature stage. Run the readiness check — it confirms both the connector install and whether alerts are flowing."

**Q: "What about Microsoft Sentinel data lake for GCC?"**
> "Commercial launched July 2025. GCC availability is pending. For now, plan on analytics-tier-only for GCC deployments and revisit table tier split when the data lake lights up in your environment."

---

## What stays the same from commercial

- The same 3 connectors: Microsoft Defender XDR (`MicrosoftThreatProtection`), Microsoft 365 Insider Risk Management (`OfficeIRM`), Office 365 (`Office365`)
- The same 4 analytics rules (DLP, IRM, LabelDowngrade, MassDownloadAfterDLP)
- The same IRM auto-triage playbook with managed identity + role-based wiring
- The same workbook + workbook panels
- The same teardown safety gates
- The same signal-to-incident story

All deploy identically in GCC — only the Azure endpoints and some feature-availability caveats differ.
