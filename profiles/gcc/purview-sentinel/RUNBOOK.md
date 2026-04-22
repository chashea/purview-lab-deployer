# Purview → Sentinel Lab — Post-Deploy Runbook (GCC)

Post-deployment steps for the GCC deployment. See the [commercial RUNBOOK](../../commercial/purview-sentinel/RUNBOOK.md) for the full flow; this document captures GCC-specific deltas.

## GCC-specific prerequisites

- `az cloud set --name AzureUSGovernment` before `az login`
- Azure Government subscription (GCC, not GCC High or DoD)
- Microsoft 365 G5 (GCC) and Sentinel available in your tenant

## 1. Run the readiness check

```powershell
./scripts/Test-SentinelReady.ps1 -LabProfile purview-sentinel -Cloud gcc `
    -SubscriptionId <gcc-subscription-guid>
```

## 2. Defender XDR connector consent

Same as commercial — requires tenant admin consent on the connector. In GCC tenants, the Defender XDR connector is generally available; confirm in your tenant via the Sentinel portal.

## 3. Insider Risk Management SIEM export

IRM availability in GCC can lag commercial. If Purview → Settings → Insider Risk Management → Export alerts is unavailable, the `OfficeIRM` connector will install but won't receive alerts. Check MS Learn service descriptions for current GCC availability.

## 4. Defender portal

GCC rollout for the Defender portal Sentinel experience is on a separate schedule. If it's not yet available in your tenant:

- The commercial RUNBOOK's "unified portal" messaging doesn't apply today
- Continue using `portal.azure.us` → Microsoft Sentinel for now
- Azure portal retirement timeline (March 31, 2027) applies to commercial; GCC retirement timeline may differ — check MS Learn announcements

## 5. Sentinel data lake tier

Data lake tier (commercial GA July 2025) may not be available in GCC. If the Tables blade doesn't expose tier switching, skip this step and retain analytics-tier only.

## 6. Microsoft Purview Content Hub solution

The Microsoft Purview solution in Content Hub is available in GCC. Install it per the commercial RUNBOOK section 5 — same flow, same rules.

## 7. Seed alerts

```powershell
./scripts/Invoke-SmokeTest.ps1 -ConfigPath ./configs/gcc/purview-sentinel-demo.json
```

## 8. Teardown

Identical safety gates to commercial. See commercial RUNBOOK section 8.

```powershell
./Remove-Lab.ps1 -Cloud gcc -LabProfile purview-sentinel `
    -ManifestPath ./manifests/gcc/PVSentinel_<timestamp>.json `
    -SubscriptionId <gcc-subscription-guid>
```

## Verification checklist (GCC-specific)

- [ ] Azure CLI is on `AzureUSGovernment` cloud (`az cloud show` confirms)
- [ ] Resource group deployed to `usgovvirginia` (or configured GCC region)
- [ ] Sentinel workspace visible at `portal.azure.us`
- [ ] Defender XDR connector consented (or note unavailability if GCC rollout pending)
- [ ] IRM connector confirmed available in your GCC tenant (per service description)
- [ ] Analytics rules enabled
- [ ] Test email flowed through to `SecurityAlert`
