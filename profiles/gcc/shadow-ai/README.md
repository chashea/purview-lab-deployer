# Shadow AI deployment guide (GCC)

This folder documents the dedicated Shadow AI deployment track for GCC tenants.

## Config and scope

- Config file: `../../../configs/gcc/shadow-ai-demo.json`
- Prefix boundary: `PVShadowAI`
- Cloud: gcc
- Purpose: deploy and remove Shadow AI controls independently from baseline `full-demo`.

## Deploy

```powershell
./Deploy-Lab.ps1 -ConfigPath configs/gcc/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud gcc
```

## Remove

```powershell
./Remove-Lab.ps1 -ConfigPath configs/gcc/shadow-ai-demo.json -TenantId <tenant-guid> -Cloud gcc -Confirm:$false
```

## What this deployment includes

- Shadow AI users and governance groups
- DLP policies for visibility, guardrails, high-risk block, and label-driven restriction
- AI-focused sensitivity labels and auto-label policy
- Shadow AI retention policies
- eDiscovery Shadow AI case
- Communication Compliance policy
- Insider Risk policy (`Risky AI usage`)
- Seeded Shadow AI test messages

## Validation notes

- Deploy runs DLP preflight checks and post-deploy validation.
- If some tenant cmdlet parameters are unsupported, deployment degrades gracefully and logs warnings.
- GCC environments may have reduced cmdlet availability; unsupported workloads are skipped with warnings.
