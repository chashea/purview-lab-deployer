---
name: smoke
description: Run smoke test against a deployed lab to confirm workloads are functional.
user_invocable: true
---

Run smoke tests against a live deployment.

## Available smoke scripts

- `scripts/Invoke-SmokeTest.ps1` — general lab smoke test
- `scripts/Test-CopilotDlpReady.ps1` — Copilot DLP profile only
- `scripts/Test-ShadowAiReady.ps1` — Shadow AI profile only
- `scripts/Test-SentinelReady.ps1` — Sentinel integration prereq check
- `scripts/Test-SentinelLab.ps1` — full Sentinel lab smoke

## Steps

1. Resolve which smoke script matches the deployed profile (ask user or infer from `$ARGUMENTS`).
2. Verify auth via `/check-graph` first — abort if Graph/EXO/Az contexts aren't right.
3. Run the script:
   ```powershell
   ./scripts/<Script>.ps1 [-Cloud commercial|gcc] [-Tenant <tenantId>]
   ```
4. Report pass/fail per workload check. On fail, surface the exact assertion that failed and which Graph/EXO call returned what.

## Don't

- Don't assume hardcoded tenant IDs in scripts are right — pass `-Tenant` explicitly when targeting a non-default tenant.
