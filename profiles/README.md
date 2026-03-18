# Profiles

This folder contains deployment capability profiles used by `Deploy-Lab.ps1` and `Remove-Lab.ps1`.

## Active cloud profiles

- `commercial/capabilities.json` - commercial tenant workload capabilities
- `gcc/capabilities.json` - GCC tenant workload capabilities

These are selected by the `-Cloud` parameter (`commercial` or `gcc`).

## Shadow AI profiles

- `commercial/shadow-ai/capabilities.json` - Shadow AI scenario profile for commercial
- `commercial/shadow-ai/README.md` - Shadow AI deployment guide (commercial)

Shadow AI profiles are documentation/scenario metadata and do not replace cloud routing.

```powershell
# Commercial
./Deploy-Lab.ps1 -ConfigPath configs/commercial/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud commercial
```
