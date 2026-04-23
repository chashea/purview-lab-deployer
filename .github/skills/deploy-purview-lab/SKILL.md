---
name: deploy-purview-lab
description: Deploy or dry-run the Purview demo lab using repository scripts, cloud profiles, and workload compatibility checks. Covers the three canonical profiles (basic, ai, purview-sentinel).
---

Use this skill when the task is to deploy lab resources, validate a config, or troubleshoot deploy flow.

## Profiles at a glance

| Profile | Config | Prefix | Notes |
|---|---|---|---|
| basic | `configs/<cloud>/basic-demo.json` | PVLab | Core Purview (non-AI) compliance workloads |
| ai | `configs/<cloud>/ai-demo.json` | PVAI | Integrated Copilot DLP + Shadow AI (Endpoint/Browser/Network) + Sentinel. Needs Azure sub. |
| purview-sentinel | `configs/<cloud>/purview-sentinel-demo.json` | PVSentinel | Sentinel + Purview signal integration. Needs Azure sub. |

Each profile has its own lifecycle and prefix — they can coexist or replace each other.

## Procedure

1. **Pick cloud/config.** Use the profile shorthand for the common path:
   ```powershell
   ./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai -TenantId <tenant> -SubscriptionId <sub>
   ```
   Resolve cloud using `-Cloud` first, then config `cloud`, then default (`commercial`).

2. **Dry-run first when making changes:**
   ```powershell
   ./Deploy-Lab.ps1 -Cloud commercial -LabProfile ai -SkipAuth -WhatIf
   ```

3. **Subscription ID for Sentinel-backed profiles:** `ai` and `purview-sentinel` require `-SubscriptionId <guid>` (or `PURVIEW_SUBSCRIPTION_ID` env var). The configs ship with empty subscriptionId — no tenant-specific GUIDs in the repo.

4. **Readiness checks after deploy** (before presenting):
   ```powershell
   # ai profile — run all three against the unified config
   ./scripts/Test-CopilotDlpReady.ps1 -LabProfile ai -Cloud commercial
   ./scripts/Test-ShadowAiReady.ps1   -LabProfile ai -Cloud commercial
   ./scripts/Test-SentinelReady.ps1   -LabProfile ai -Cloud commercial -SubscriptionId <sub>

   # Sentinel-only profile
   ./scripts/Test-SentinelReady.ps1   -LabProfile purview-sentinel -Cloud commercial -SubscriptionId <sub>

   # Endpoint DLP domain block list push (tenant-wide setting; preview + apply)
   ./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile ai -Cloud commercial
   ./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile ai -Cloud commercial -Apply
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

- **First `ai` deploy sometimes exits non-zero even on success:** the validation-summary block throws if any AI-Applications retention policy is still invisible to `Get-*CompliancePolicy`. Policies are actually written; manifest is exported before the throw. Re-run picks up any remaining gaps cleanly.
- **Copilot Prompt SIT DLP rule fails to PUT with "RestrictAccess or RestrictWebGrounding are required":** known MS-side issue with the SIT-rule shape. Label-based Copilot rule works. Plan on manual portal config for the SIT rules or leave them as policy-without-rules.
- **SensitivityLabels step may throw `LabelAlreadyPublishedException` on re-run:** label publication step isn't idempotent. Error-isolated — DLP, retention, Sentinel all continue.

## Repository-specific guardrails

- Do not bypass capability gating from `profiles/<cloud>/capabilities.json`; deploy must block workloads marked `unavailable`.
- Keep `SupportsShouldProcess` / `-WhatIf` behavior intact.
- Preserve module import pattern from `Deploy-Lab.ps1` (`modules/*.psm1`).
- Profiles are separate tracks — different config, prefix, and lifecycle. The `ai` profile intentionally unifies Copilot DLP + Shadow AI + Sentinel under one prefix (`PVAI`).
- Sentinel teardown is safety-gated: `-ForceDeleteResourceGroup` requires manifest + `createdBy=purview-lab-deployer` tag + name match.
