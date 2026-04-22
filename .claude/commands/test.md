---
name: test
description: Run Pester tests under tests/. CI uses the same invocation.
user_invocable: true
---

Run the Pester suite.

```powershell
Invoke-Pester tests/ -Output Detailed
```

## Behavior

1. Run the command. If a path is supplied via `$ARGUMENTS` (e.g., `tests/DLP.Tests.ps1`), run only that file.
2. On failure: investigate the failing test, identify root cause (test bug vs. module bug), fix it, re-run only that test to confirm.
3. On pass: report `passed/failed/skipped` counts only. No verbose output dump.

## Don't

- Don't suppress failing tests with `-Skip` to make CI green — root-cause and fix.
- Don't add `-Tag` filters that hide work.
