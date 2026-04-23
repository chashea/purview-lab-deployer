# Integrated AI Governance Lab — Post-Deploy Runbook (Commercial)

Post-deployment steps and demo-day preparation. This lab bundles Copilot DLP + Shadow AI (Endpoint / Browser / Network) + Sentinel under a single `PVAI` prefix — see `profiles/commercial/purview-sentinel/RUNBOOK.md` for deeper SOC-side guidance; this document covers the integrated flow.

## Prerequisites

- Microsoft 365 E5 (or E5 Compliance add-on)
- Microsoft 365 Copilot licenses assigned to demo users
- Azure subscription with Owner/Contributor
- Microsoft Defender for Endpoint onboarded on at least one test device
- Insider Risk SIEM export available in your tenant (Purview → Settings → Insider Risk Management → Export alerts)

---

## 1. Run all three readiness checks

```powershell
./scripts/Test-CopilotDlpReady.ps1 -ConfigPath ./configs/commercial/ai-demo.json -Cloud commercial
./scripts/Test-ShadowAiReady.ps1   -ConfigPath ./configs/commercial/ai-demo.json -Cloud commercial
./scripts/Test-SentinelReady.ps1   -ConfigPath ./configs/commercial/ai-demo.json -Cloud commercial -SubscriptionId <sub>
```

Green across all three = lab is integrated-ready. The Sentinel check will also flag missing Copilot DLP or Shadow AI signal flow via the 24h data-flow check.

Deep smoke test:

```powershell
./scripts/Test-SentinelLab.ps1 -ConfigPath ./configs/commercial/ai-demo.json
```

---

## 2. Push Endpoint DLP browser-and-domain restrictions

Tenant-wide setting; the config lists 10 AI sites to block. Review before applying (this touches settings shared by other DLP policies):

```powershell
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -ConfigPath ./configs/commercial/ai-demo.json
# Review, then:
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -ConfigPath ./configs/commercial/ai-demo.json -Apply
```

---

## 3. Grant Defender XDR connector consent

Sentinel portal → Data connectors → Microsoft Defender XDR → Connect. Requires tenant admin. Without this, the DLP + IRM signals don't flow to Sentinel.

Full walkthrough: see `profiles/commercial/purview-sentinel/RUNBOOK.md` section 2.

---

## 4. Enable Insider Risk SIEM export

Purview portal → Settings → Insider Risk Management → Export alerts → On.

This is what lets the `PVAI-RiskyAIUsageCorrel` cross-table Sentinel rule actually fire — without it, the IRM side of the correlation stays empty.

---

## 5. Device onboarding

At least one test device must be onboarded to Microsoft Defender for Endpoint for the Shadow AI paste/upload demos to produce live blocks. If devices aren't onboarded, the `Shadow AI - Endpoint Protection` policy audits but doesn't block.

Full walkthrough: `profiles/commercial/shadow-ai/RUNBOOK.md` section 3.

---

## 6. Optional: Activate DSPM for AI

DSPM for AI is Microsoft's recommended "front door" for AI security posture. Enables one-click policies that complement this lab's custom controls.

1. Purview portal → **Solutions** → **DSPM for AI**
2. Under **Get started**, enable prerequisites (audit is usually auto-on for new tenants; browser extension + device onboarding are required for full third-party AI visibility)
3. Under **Recommendations**, activate:
   - **Fortify your data security** (one-click DLP policies for external AI block + Copilot protection)
   - **Detect risky interactions in AI apps** (IRM for Risky AI Usage)
   - **Detect unethical behavior in AI apps** (Communication Compliance)
   - **Extend your insights for data discovery** (Edge collection policy + site-visit IRM)
   - **Secure interactions in Microsoft Copilot experiences** (Copilot collection policy)
   - **Secure interactions from enterprise apps** (Entra-registered AI / ChatGPT Enterprise / Foundry collection)

Wait 24 hours, then check **DSPM for AI → Reports** for aggregated views (Sensitive interactions per generative AI app, Top sensitive info types, Insider risk severity per AI app).

> **Positioning:** This lab is the enforcement surface. DSPM for AI is the posture surface. Enforcement + posture is the complete AI security story.

---

## 7. Optional: Microsoft Purview Content Hub solution

Already declared in the config's `additionalContentHubSolutions` list — the deployer attempts the install. If it's missing after deploy (check deploy log):

1. Sentinel portal (or Defender portal → Sentinel) → **Content Hub**
2. Search **Microsoft Purview**
3. Install

This ships MS-maintained analytics rules (`Sensitive Data Discovered in the Last 24 Hours`) that query `PurviewDataSensitivityLogs` — complementary to our custom rules.

---

## 8. Seed signals before a live demo

Integrated demos need all three signal sources actively flowing. Seed 30-60 min before demo time:

```powershell
# Send test emails (triggers DLP + Defender XDR flow to Sentinel)
./scripts/Invoke-SmokeTest.ps1 -ConfigPath ./configs/commercial/ai-demo.json
```

Manual supplementary prompts:
- Copilot DLP: prompts from `scripts/copilot-test-prompts.md` (SSN/CC/PHI in Copilot chat)
- Shadow AI: prompts from `scripts/shadow-ai-test-prompts.md` (paste/upload to external AI)

Running both prompt libraries from the same demo user triggers the cross-signal `PVAI-RiskyAIUsageCorrel` rule within ~4 hours.

---

## 9. Defender portal (recommended)

Onboard the workspace to the Defender portal for the unified SecOps experience. New Sentinel customers after July 1, 2025 auto-onboard; existing workspaces opt in.

1. Sign into [security.microsoft.com](https://security.microsoft.com)
2. Microsoft Sentinel → connect workspace `PVAI-ws`
3. After onboarding: Defender portal → Microsoft Sentinel → your rules, connectors, workbooks, incidents all appear alongside Defender XDR signals in advanced hunting

---

## 10. Teardown verification

Teardown is safety-gated (same gates as the sentinel profile).

### Non-destructive (default — preserves Azure resources)

```powershell
./Remove-Lab.ps1 -Cloud commercial -LabProfile ai `
    -ManifestPath ./manifests/commercial/PVAI_<timestamp>.json `
    -SubscriptionId <subscription-guid>
```

Removes all Purview policies, labels, rules, and Sentinel child resources (connectors, rules, workbooks, playbook). Resource group + workspace persist for re-deploy.

### Destructive (deletes Azure resource group)

Requires ALL:
- `-ForceDeleteResourceGroup` switch
- `-ManifestPath`
- Manifest `createdResourceGroup: true`
- RG tags include `createdBy=purview-lab-deployer`
- Name + subscription match

```powershell
./Remove-Lab.ps1 -Cloud commercial -LabProfile ai `
    -ManifestPath ./manifests/commercial/PVAI_<timestamp>.json `
    -SubscriptionId <subscription-guid> -ForceDeleteResourceGroup
```

### Verify clean teardown

```bash
az resource list --resource-group PVAI-rg --subscription <sub> --output table
# Should be empty after destructive teardown
```

---

## Verification checklist

- [ ] All three readiness scripts return READY
- [ ] Endpoint DLP domain block list pushed
- [ ] Defender XDR connector consented
- [ ] IRM SIEM export toggled on
- [ ] Microsoft 365 Copilot licenses assigned to demo users
- [ ] Test device onboarded to Defender for Endpoint
- [ ] Test documents uploaded to OneDrive and auto-labeled (check deploy log)
- [ ] `SecurityAlert` rows present in Sentinel workspace (24h window)
- [ ] All 7 analytics rules enabled
- [ ] Both workbooks rendered
- [ ] IRM auto-triage playbook + automation rule deployed
- [ ] (Optional) Microsoft Purview Content Hub solution installed
- [ ] (Optional) DSPM for AI activated
- [ ] (Optional) Workspace onboarded to Defender portal
- [ ] Seed signals generated (smoke test + prompt libraries)

---

## Switching from simulation to enforcement

DLP policies deploy in `TestWithNotifications` by default. Switch to enforce when ready:

1. Purview portal → DLP → Policies
2. Select each `PVAI-*` policy
3. Change status: Test it out → Turn it on
4. Allow 4h for propagation

> **Caution:** Switching restarts the 4-hour propagation window. Rerun the readiness scripts before demoing after any mode change.
