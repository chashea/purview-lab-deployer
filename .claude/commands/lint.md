---
name: lint
description: Run PSScriptAnalyzer with the repo's CI rules. Zero warnings required.
user_invocable: true
---

Run the same lint pass CI runs.

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
```

## Behavior

1. Run the command above.
2. If zero output → pass. Done.
3. If output → report each finding as `file:line — RuleName — Message`. Group by file.
4. If user asks to fix, fix one finding at a time; do not bulk-rewrite. Re-run lint after each fix to confirm.

## Install (if cmdlet missing)

```powershell
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```
