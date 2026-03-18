# Profiles

This folder contains deployment capability profiles used by `Deploy-Lab.ps1` and `Remove-Lab.ps1`.

## Active cloud profiles

- `commercial/capabilities.json` - commercial tenant workload capabilities
- `gcc/capabilities.json` - GCC tenant workload capabilities

These are selected by the `-Cloud` parameter (`commercial` or `gcc`).

## Basic lab profiles

- `commercial/basic-lab/README.md` - Basic lab deployment guide (commercial)
- `gcc/basic-lab/README.md` - Basic lab deployment guide (GCC)

```powershell
# Commercial
./Deploy-Lab.ps1 -Cloud commercial -LabProfile basic-lab -TenantId <tenant-guid>

# GCC
./Deploy-Lab.ps1 -Cloud gcc -LabProfile basic-lab -TenantId <tenant-guid>
```

## Shadow AI profiles

- `commercial/shadow-ai/capabilities.json` - Shadow AI scenario profile for commercial
- `commercial/shadow-ai/README.md` - Shadow AI deployment guide (commercial)
- `gcc/shadow-ai/capabilities.json` - Shadow AI scenario profile for GCC
- `gcc/shadow-ai/README.md` - Shadow AI deployment guide (GCC)

Shadow AI profiles are documentation/scenario metadata and do not replace cloud routing.

```powershell
# Commercial
./Deploy-Lab.ps1 -Cloud commercial -LabProfile shadow-ai -TenantId <tenant-guid>

# GCC
./Deploy-Lab.ps1 -Cloud gcc -LabProfile shadow-ai -TenantId <tenant-guid>
```
