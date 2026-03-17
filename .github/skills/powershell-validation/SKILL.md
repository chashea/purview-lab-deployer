---
name: powershell-validation
description: Run repository-standard PowerShell validation for this project using CI-aligned PSScriptAnalyzer commands and targeted single-file checks.
---

Use this skill when asked to lint/validate changes in this repository.

## Validation commands

```powershell
# Install validation dependency
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser

# Full repository validation (matches CI workflow)
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns

# Targeted single-file validation
Invoke-ScriptAnalyzer -Path ./Deploy-Lab.ps1 -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
Invoke-ScriptAnalyzer -Path ./Remove-Lab.ps1 -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
```

## Repo-specific expectations

- Treat analyzer warnings as failures (CI throws if any are returned).
- There is no dedicated Pester suite in this repository; use analyzer + `-WhatIf` smoke checks for deploy/remove script changes.
