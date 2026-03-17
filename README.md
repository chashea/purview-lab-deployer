# purview-lab-deployer

Automated Microsoft Purview lab deployment using PowerShell 7+, config files, and workload modules.

## Documentation map

- Commercial guide: `configs/commercial/README.md`
- GCC guide: `configs/gcc/README.md`
- Shadow AI guide: `shadow-ai/README.md`
- Profiles guide: `profiles/README.md`

## Shared prerequisites

- PowerShell 7+ (`pwsh`)
- `ExchangeOnlineManagement` >= 3.0
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Users`
- `Microsoft.Graph.Groups`
- Roles: Compliance Administrator, User Administrator, eDiscovery Administrator

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
```

## Quick start

```powershell
# Interactive
./Deploy-Lab-Interactive.ps1
./Remove-Lab-Interactive.ps1

# Explicit
./Deploy-Lab.ps1 -ConfigPath <config-path> -TenantId <tenant-guid> -Cloud <commercial|gcc>
./Remove-Lab.ps1 -ConfigPath <config-path> -TenantId <tenant-guid> -Cloud <commercial|gcc>
```

Set default environment variables if desired:

```powershell
$env:PURVIEW_TENANT_ID = '<tenant-guid>'
$env:PURVIEW_CLOUD = 'commercial'  # or 'gcc'
```

## Validation

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
```
