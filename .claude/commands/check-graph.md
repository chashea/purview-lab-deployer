---
name: check-graph
description: Verify MgGraph + ExchangeOnline + Az contexts before running Deploy-Lab. Fast sanity check.
user_invocable: true
---

Verify auth state before any deploy/remove.

## Run these in order

```powershell
# Graph context
$mg = Get-MgContext
"Graph tenant: $($mg.TenantId)"
"Graph account: $($mg.Account)"
"Graph scopes: $($mg.Scopes -join ', ')"

# Az context (only matters for ai / purview-sentinel profiles)
$az = Get-AzContext -ErrorAction SilentlyContinue
if ($az) { "Az tenant: $($az.Tenant.Id), sub: $($az.Subscription.Name)" } else { "Az: not connected" }

# EXO session
Get-ConnectionInformation -ErrorAction SilentlyContinue | Select-Object UserPrincipalName, TenantId, State
```

## Validate

- Tenant ID matches expected (commercial `f1b92d41-6d54-4102-9dd9-4208451314df` or GCC `119e9fe0-c9d3-4a9d-be8b-c82d03fd0cd4`)
- Required Graph scopes present — cross-reference against `modules/Prerequisites.psm1`
- EXO session is `Connected`, not `Broken`

## On failure

Hand off to `graph-auth-debugger` agent with the specific failure (missing scope name, wrong tenant, expired token).

## Output

Single table: Service | Tenant | Account | Status | Issues
