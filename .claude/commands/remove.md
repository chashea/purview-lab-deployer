---
name: remove
description: Tear down a Purview lab — manifest-based when available, prefix fallback otherwise.
user_invocable: true
---

Tear down a deployed Purview lab via `Remove-Lab.ps1`.

## Steps

1. **Confirm scope** — ask (or take from `$ARGUMENTS`):
   - Cloud: `commercial` or `gcc`
   - Profile or config path
   - Manifest path (optional but strongly preferred for precision)
2. **Locate manifest** — if not provided, list `manifests/<cloud>/*.json` sorted newest-first; offer the most recent matching the prefix.
3. **Audit manifest first** — delegate to `manifest-auditor` agent to verify the manifest is valid and matches tenant state. Abort if the manifest is corrupt.
4. **Confirm destructive action** — show resource counts to be removed; require explicit "yes" before running.
5. **Run teardown**:
   ```powershell
   ./Remove-Lab.ps1 -ConfigPath configs/<cloud>/<config>.json -Cloud <cloud> [-ManifestPath <path>]
   ```
6. **Verify** — re-run `manifest-auditor` zombie-detection check. Surface any resources that survived removal.

If user confirms `-WhatIf` mode, skip the destructive-action confirmation but still show the dry-run output.
