# Profiles

This folder contains deployment capability profiles used by `Deploy-Lab.ps1` and `Remove-Lab.ps1`.

## Active cloud profiles

- `commercial/capabilities.json` - commercial tenant workload capabilities
- `gcc/capabilities.json` - GCC tenant workload capabilities

These are selected by the `-Cloud` parameter (`commercial` or `gcc`).

## Shadow AI profile

- `shadow-ai/capabilities.json` - scenario-specific Shadow AI guidance profile

The Shadow AI profile is documentation/scenario metadata and does not replace cloud routing.
Use Shadow AI deployment with:

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/commercial/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud commercial
```
