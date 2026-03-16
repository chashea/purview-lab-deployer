# CLAUDE.md — purview-lab-deployer

## Project Overview
Automated Microsoft Purview demo lab deployment via PowerShell 7+.
Config-driven, modular by workload, deploy + teardown symmetry.

## Stack
- PowerShell 7+ (pwsh)
- ExchangeOnlineManagement >= 3.0
- Microsoft.Graph SDK (Users, Groups, Authentication)

## Tenant
- ID: `f1b92d41-6d54-4102-9dd9-4208451314df`
- Domain: `MngEnvMCAP648165.onmicrosoft.com`

## Conventions
- All resources prefixed with `{config.prefix}-` for reliable teardown
- Every workload module exports `Deploy-<Workload>` and `Remove-<Workload>`
- Idempotent: check existence before creating
- `-WhatIf` support on all deploy/remove functions
- Lint with PSScriptAnalyzer — zero warnings required

## Running
```powershell
# Deploy
./Deploy-Lab.ps1 -ConfigPath configs/full-demo.json

# Dry run
./Deploy-Lab.ps1 -ConfigPath configs/full-demo.json -WhatIf

# Teardown
./Remove-Lab.ps1 -ConfigPath configs/full-demo.json
```

## Testing
```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning
```
