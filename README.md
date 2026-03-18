# purview-lab-deployer

Automated Microsoft Purview lab deployment using PowerShell 7+, config files, and workload modules.

## Documentation map

- Commercial guide: `configs/commercial/README.md`
- GCC guide: `configs/gcc/README.md`
- Shadow AI guide (commercial): `profiles/commercial/shadow-ai/README.md`
- Profiles guide: `profiles/README.md`

## Workload modules

| Module | Automated | Notes |
|--------|-----------|-------|
| TestUsers | Full | Create or reference existing Entra ID users and groups |
| CustomSensitiveInfoTypes | Full | Custom SIT patterns for DLP |
| SensitivityLabels | Full | Labels and auto-label policies |
| DLP | Full | Policies and rules with enforcement config |
| Retention | Full | Retention policies and labels |
| EDiscovery | Full | Cases, custodians, holds, searches |
| CommunicationCompliance | Full | Supervision policies |
| InsiderRisk | Full | Insider risk management policies |
| ConditionalAccess | Full | CA policies (report-only mode) |
| AppGovernance | Hybrid | MDCA app tagging via API; discovery/session policies via API; OAuth app governance logged as manual portal steps |
| AuditConfig | Full | Audit log searches |
| TestData | Full | Send test emails with sensitive content |

## Shared prerequisites

- PowerShell 7+ (`pwsh`)
- `ExchangeOnlineManagement` >= 3.0
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Users`
- `Microsoft.Graph.Groups`
- `Microsoft.Graph.Identity.SignIns`
- Roles: Compliance Administrator, User Administrator, eDiscovery Administrator

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
```

## Quick start

```powershell
# Clone the repo and navigate to it
git clone https://github.com/chashea/purview-lab-deployer.git
cd purview-lab-deployer

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

## Test users mode

The `testUsers` workload supports two modes via the `mode` field in config:

| Mode | Description |
|------|-------------|
| `create` | (Default) Creates new users and groups in Entra ID. Assigns licenses automatically. |
| `existing` | Validates that pre-existing Entra ID users are present. Creates groups and adds those users as members. Does not create or delete users. |

### Using existing users

Set `"mode": "existing"` and specify users by UPN instead of the full user object:

```json
"testUsers": {
  "enabled": true,
  "mode": "existing",
  "users": [
    { "upn": "rtorres@contoso.onmicrosoft.com" },
    { "upn": "mchen@contoso.onmicrosoft.com" }
  ],
  "groups": [
    { "displayName": "PVLab-Finance-Team", "members": ["mchen"] }
  ]
}
```

Key behaviors in `existing` mode:
- Deployment fails if any referenced UPN is not found in Entra ID
- License assignment is skipped (existing users are assumed to be licensed)
- Groups are still created and managed by the lab
- Removal only deletes groups; users are never deleted
- Group `members` use the mailNickname (UPN local part before `@`)

See `configs/commercial/existing-users-demo.json` for a full example.

## Validation

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
```
