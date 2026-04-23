# Smoke tests

Post-deploy verification that the lab's DLP, Copilot, Insider Risk, and Sentinel surfaces are firing correctly. Run these after `Deploy-Lab.ps1` finishes and the DLP propagation window has passed (15–60 min for DLP alerts, 24–48 hrs for IRM risk signals).

All smoke-test scripts live in `scripts/`. The main entry is `Invoke-SmokeTest.ps1`.

---

## Before sharing with teammates

Auto-discover mode picks the **first 2 alphabetically-sorted licensed mailbox users** in the tenant — in a production tenant that is often an executive or real employee's inbox. Always:

- **Preview with `-WhatIf` first**, or
- Run against a lab tenant when possible, or
- Pass `-Users alice@...,bob@...` to target known lab accounts.

The script also requires the `ExchangeOnlineManagement` module for `-ValidateOnly` audit-log checks, plus Graph scopes `Mail.Send`, `User.Read.All`, `Files.ReadWrite.All`, `Sites.ReadWrite.All`, and `Organization.Read.All` (consented on first interactive run).

---

## DLP smoke test — `Invoke-SmokeTest.ps1`

Sends emails and uploads OneDrive files containing fake sensitive data (SSN, Credit Card, bank account, medical terms) so you can watch DLP policies fire in real time.

### Option A — Auto-discover (zero args, works in ANY Purview tenant)

```powershell
# Preview first — shows the tenant + users it will target
./scripts/Invoke-SmokeTest.ps1 -WhatIf

# Go
./scripts/Invoke-SmokeTest.ps1
```

### Option B — Standalone (explicit tenant + users)

```powershell
./scripts/Invoke-SmokeTest.ps1 `
    -TenantId "YOUR-TENANT-ID" `
    -Domain "YOUR-TENANT.onmicrosoft.com" `
    -Users "user1@YOUR-TENANT.onmicrosoft.com","user2@YOUR-TENANT.onmicrosoft.com"
```

### Option C — Config mode (uses a deployed lab config)

```powershell
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -Cloud commercial
./scripts/Invoke-SmokeTest.ps1 -ConfigPath configs/commercial/my-lab.json -Cloud commercial
```

### Insider Risk burst activity

Add `-BurstActivity` to any mode for high-volume behaviour that triggers IRM score rises (10 rapid emails + 15 file uploads + 5 sharing links from the same user):

```powershell
# Auto-discover + burst
./scripts/Invoke-SmokeTest.ps1 -BurstActivity

# Config + burst
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -BurstActivity
```

IRM signals take 24–48 hours to aggregate into risk scores.

### Validate matches in the audit log

After running, check Unified Audit for `DlpRuleMatch` events tagged with the smoke-test run ID:

```powershell
./scripts/Invoke-SmokeTest.ps1 -ValidateOnly -Since (Get-Date).AddHours(-1)
# Or with a specific config
./scripts/Invoke-SmokeTest.ps1 -LabProfile basic -ValidateOnly -Since (Get-Date).AddHours(-1)
```

---

## Copilot-specific tests

### Copilot DLP prompts (manual)

Open [M365 Copilot Chat](https://m365.cloud.microsoft/chat) and paste prompts from `scripts/copilot-test-prompts.md` (commercial) or `scripts/copilot-label-test-prompts-gcc.md` (GCC — label-only, no SIT-based prompt blocking). Each prompt is designed to trigger Copilot DLP classifiers.

### Copilot DLP API (scripted)

```powershell
./scripts/Invoke-CopilotChatTest.ps1
```

Fires the label-block prompt set at the M365 Copilot Chat API (`/beta/copilot/conversations`) and logs the raw responses for pass/block analysis.

### Shadow AI external sites (manual)

Copy prompts from `scripts/shadow-ai-test-prompts.md` and paste into ChatGPT / Claude / Gemini (from a managed device) to exercise Endpoint DLP paste blocks, Browser Data Security, and Network Data Security.

---

## AI profile readiness gates

Before a live demo, run the per-surface readiness checks against the `ai` profile config. Each returns `Ready / Wait / Blocked` with exit codes 0 / 1 / 2:

```powershell
./scripts/Test-CopilotDlpReady.ps1 -LabProfile ai -Cloud commercial
./scripts/Test-ShadowAiReady.ps1   -LabProfile ai -Cloud commercial
./scripts/Test-SentinelReady.ps1   -LabProfile ai -Cloud commercial -SubscriptionId <sub>
```

Push the tenant-wide Endpoint DLP domain block list (preview, then apply):

```powershell
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile ai -Cloud commercial
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile ai -Cloud commercial -Apply
```

---

## Sentinel end-to-end smoke test

Deep smoke for the `purview-sentinel` or `ai` profile (CI-grade; read-only; exits non-zero on failure):

```powershell
pwsh ./scripts/Test-SentinelLab.ps1 -ConfigPath ./configs/commercial/purview-sentinel-demo.json
pwsh ./scripts/Test-SentinelLab.ps1 -ConfigPath ./configs/commercial/ai-demo.json
```

Verifies the workspace, Sentinel onboarding, expected data connectors (live or installed via Content Hub), every analytics rule (including entity mappings), the workbook, the IRM auto-triage playbook, and the automation rule.

---

## Where to look after a smoke test

| Surface | Portal URL | Latency |
|---|---|---|
| DLP alerts | https://purview.microsoft.com/datalossprevention/alerts | 15–60 min |
| Activity Explorer | https://purview.microsoft.com/datalossprevention/activityexplorer | 15–60 min |
| Insider Risk alerts | https://purview.microsoft.com/insiderriskmanagement/alerts | 24–48 hrs |
| Audit Log | https://purview.microsoft.com/audit | ~15 min |
| Sentinel incidents (ai / purview-sentinel profiles) | Azure portal → Sentinel workspace → Incidents | 30–60 min after Defender XDR connector consent |

---

## Scheduled smoke test (CI)

A GitHub Actions workflow runs `Invoke-SmokeTest.ps1` daily at 10 AM ET on weekdays (`.github/workflows/daily-smoke-test.yml`). Requires OIDC federated credentials — see the [README](README.md#oidc-setup-for-daily-smoke-tests) for setup.

---

## Troubleshooting

| Issue | Fix |
|---|---|
| No DLP alerts after smoke test | Wait 15–60 minutes; check rules have alerting enabled in Purview → DLP → Policies |
| OneDrive uploads fail with 404 | Users haven't had OneDrive provisioned. Visit onedrive.com as each user once, or run `./scripts/Request-OneDriveProvisioning.ps1 -LabProfile <profile> -Wait` |
| Insider Risk shows no alerts | IRM needs 24–48 hours for signal aggregation; confirm policies are *Enabled* (not *In Test*) in Purview → Insider Risk → Policies |
| Auto-discover picked the wrong users | Re-run with `-Users alice@...,bob@...` to target specific lab accounts |
| `Search-UnifiedAuditLog` fails in `-ValidateOnly` | The cmdlet lives in Exchange Online PowerShell, not IPPS; script connects via `Connect-ExchangeOnline`. Ensure the account has the *View-Only Audit Logs* role. |
