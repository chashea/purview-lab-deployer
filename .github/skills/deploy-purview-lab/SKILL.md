---
name: deploy-purview-lab
description: Deploy or dry-run the Purview demo lab using repository scripts, cloud profiles, and workload compatibility checks. Covers all five deployment tracks (basic-lab, shadow-ai, copilot-protection, purview-sentinel, ai-security).
---

Use this skill when the task is to deploy lab resources, validate a config, or troubleshoot deploy flow.

## Profiles at a glance

| Profile | Config | Prefix | Notes |
|---|---|---|---|
| basic-lab | `configs/<cloud>/basic-lab-demo.json` | PVLab | Core Purview (non-AI) |
| shadow-ai | `configs/<cloud>/shadow-ai-demo.json` | PVShadowAI | 5 DLP policies across Devices/Browser/Network/CopilotExperiences |
| copilot-protection | `configs/<cloud>/copilot-dlp-demo.json` | PVCopilotDLP | Focused Copilot DLP (prompt SIT + label) |
| purview-sentinel | `configs/<cloud>/purview-sentinel-demo.json` | PVSentinel | Sentinel + Purview signal integration. Needs Azure sub. |
| ai-security | `configs/<cloud>/ai-security-demo.json` | PVAISec | Integrated Copilot DLP + Shadow AI + Sentinel. Needs Azure sub. |

Each profile has its own lifecycle and prefix — they can coexist or replace each other.

## Procedure

1. **Pick cloud/config.** Use the profile shorthand for the common path:
   ```powershell
   ./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai-security -TenantId <tenant> -SubscriptionId <sub>
   ```
   Resolve cloud using `-Cloud` first, then config `cloud`, then default (`commercial`).

2. **Dry-run first when making changes:**
   ```powershell
   ./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai-security -SkipAuth -WhatIf
   ```

3. **Subscription ID for Sentinel profiles:** `purview-sentinel` and `ai-security` require `-SubscriptionId <guid>` (or `PURVIEW_SUBSCRIPTION_ID` env var). The config ships with empty subscriptionId — no tenant-specific GUIDs in the repo.

4. **Readiness checks after deploy** (before presenting):
   ```powershell
   # Per-surface gates
   ./scripts/Test-CopilotDlpReady.ps1 -LabProfile copilot-protection -Cloud commercial
   ./scripts/Test-ShadowAiReady.ps1   -LabProfile shadow-ai          -Cloud commercial
   ./scripts/Test-SentinelReady.ps1   -LabProfile purview-sentinel   -Cloud commercial -SubscriptionId <sub>

   # For ai-security — run all three against the unified config
   ./scripts/Test-CopilotDlpReady.ps1 -ConfigPath configs/commercial/ai-security-demo.json -Cloud commercial
   ./scripts/Test-ShadowAiReady.ps1   -ConfigPath configs/commercial/ai-security-demo.json -Cloud commercial
   ./scripts/Test-SentinelReady.ps1   -ConfigPath configs/commercial/ai-security-demo.json -Cloud commercial -SubscriptionId <sub>

   # Endpoint DLP domain block list push (tenant-wide setting; preview + apply)
   ./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -ConfigPath configs/commercial/ai-security-demo.json
   ./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -ConfigPath configs/commercial/ai-security-demo.json -Apply
   ```

5. **Deploy order** (enforced by Deploy-Lab.ps1):
   `testUsers → sensitivityLabels → dlp → retention → eDiscovery → communicationCompliance → insiderRisk → conditionalAccess → auditConfig → sentinelIntegration → testData → Validation`

6. **Post-deploy propagation windows** worth knowing:
   - DLP policies: up to 4h to reflect in Copilot and Copilot Chat
   - Auto-label policies: 30–90 min for newly created labels to become discoverable to `New-AutoSensitivityLabelPolicy`
   - AI-Applications retention (`MicrosoftCopilotExperiences` / `EnterpriseAIApps` / `OtherAIApps`): 10–30+ min query-cache lag before `Get-RetentionCompliancePolicy` returns; validation has tolerance for this
   - Defender XDR connector data flow: needs tenant admin consent on connector card; SecurityAlert rows flow 30–60 min after consent
   - IRM → Sentinel via OfficeIRM: requires Purview → Settings → Insider Risk Management → Export alerts = On; allow 60 min for first batch

7. **Validate outputs after successful deploy:**
   - Manifest file under `manifests/<cloud>/<prefix>_<timestamp>.json` (required for precise teardown of Sentinel RG)
   - Log transcript under `logs/`
   - DLP + Copilot license preflight run automatically at step start

## Known deploy-time quirks

- **First ai-security deploy exits non-zero even on success:** the validation-summary block throws if any AI-Applications retention policy is still invisible to `Get-*ComplianceP olicy`. Policies are actually written; manifest is exported before the throw. Re-run picks up any remaining gaps cleanly.
- **Copilot Prompt SIT DLP rule fails to PUT with "RestrictAccess or RestrictWebGrounding are required":** known MS-side issue with the SIT-rule shape. Label-based Copilot rule works. Plan on manual portal config for the SIT rules or leave them as policy-without-rules.
- **SensitivityLabels step may throw `LabelAlreadyPublishedException` on re-run:** label publication step isn't idempotent. Error-isolated — DLP, retention, Sentinel all continue.

## Repository-specific guardrails

- Do not bypass capability gating from `profiles/<cloud>/capabilities.json`; deploy must block workloads marked `unavailable`.
- Keep `SupportsShouldProcess` / `-WhatIf` behavior intact.
- Preserve module import pattern from `Deploy-Lab.ps1` (`modules/*.psm1`).
- Profiles must remain separate tracks — different config, prefix, and lifecycle. Exception: `ai-security` intentionally unifies Copilot DLP + Shadow AI + Sentinel under one prefix (`PVAISec`).
- Sentinel teardown is safety-gated: `-ForceDeleteResourceGroup` requires manifest + `createdBy=purview-lab-deployer` tag + name match.
