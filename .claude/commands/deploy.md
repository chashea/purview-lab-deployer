---
name: deploy
description: Deploy a Purview lab profile (interactive prompts for cloud + profile + flags).
user_invocable: true
---

Deploy a Purview lab profile via `Deploy-Lab.ps1`.

## Steps

1. **Confirm scope** — ask user (or accept from `$ARGUMENTS`):
   - Cloud: `commercial` or `gcc`
   - Profile: one of `basic`, `ai`, `purview-sentinel` (deprecated aliases: `basic-lab`, `shadow-ai`, `copilot-dlp`, `copilot-protection`, `ai-security`)
   - Test users: optional `-TestUsers <upn>[,<upn>...]` to override profile defaults
   - Dry run: `-WhatIf` if user wants no side effects
2. **Pre-flight** — run `Invoke-Pester tests/ -Output Detailed`. Abort on any failure.
3. **Verify auth** — confirm current Az + MgGraph contexts target the right tenant. If wrong tenant, prompt for re-auth before continuing.
4. **Deploy** — run:
   ```powershell
   ./Deploy-Lab.ps1 -LabProfile <profile> -Cloud <cloud> [-TestUsers <upns>] [-WhatIf]
   ```
5. **Post-deploy** — list the new manifest at `manifests/<cloud>/<prefix>_<timestamp>.json`. Confirm it exists and is well-formed (delegate to `manifest-auditor` agent).
6. **Report** — workloads deployed, manifest path, any warnings/skips.

If `$ARGUMENTS` is empty, prompt interactively. If args supplied (e.g., `commercial basic-lab`), parse and proceed without prompts.
