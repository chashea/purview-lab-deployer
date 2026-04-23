---
name: config-authoring
description: Step-by-step guide for creating new Purview lab config JSON files from scratch. Use when asked to create a new demo scenario, lab config, or deployment profile.
---

Use this skill when creating a new lab config file from scratch.

## Steps

1. **Choose cloud scope**: `commercial` or `gcc`. Config goes under `configs/<cloud>/`.

2. **Set required fields**:
   ```json
   {
     "labName": "<descriptive name>",
     "prefix": "<PVLab or PVShadowAI or custom>",
     "domain": "<tenant>.onmicrosoft.com",
     "cloud": "<commercial|gcc>"
   }
   ```

3. **Check workload availability**: Read `profiles/<cloud>/capabilities.json` to verify which workloads are `available`, `limited`, or `unavailable` before enabling them.

4. **Add workloads object**: Each workload needs `"enabled": true/false`. Only include workloads relevant to the scenario.

5. **Validate against schema**: The canonical schema is `configs/_schema.json`. After creating the file, verify:
   ```bash
   cat configs/<cloud>/<name>.json | python3 -m json.tool
   ```

6. **Naming convention**: Files are named `<scenario>-demo.json` (e.g., `healthcare-demo.json`).

## Minimal config template

```json
{
  "labName": "Scenario Name Lab",
  "prefix": "PVLab",
  "domain": "tenant.onmicrosoft.com",
  "cloud": "commercial",
  "workloads": {
    "testUsers": {
      "enabled": true,
      "mode": "create",
      "users": [
        {
          "displayName": "Test User 1",
          "mailNickname": "tuser1",
          "department": "IT",
          "jobTitle": "Analyst",
          "usageLocation": "US"
        }
      ],
      "groups": []
    },
    "sensitivityLabels": { "enabled": false },
    "dlp": { "enabled": false },
    "retention": { "enabled": false },
    "eDiscovery": { "enabled": false },
    "communicationCompliance": { "enabled": false },
    "insiderRisk": { "enabled": false },
    "conditionalAccess": { "enabled": false },
    "testData": { "enabled": false },
    "auditConfig": { "enabled": false }
  }
}
```

## Reference configs

Use existing configs as templates for different complexity levels:
- **Full-featured baseline**: `configs/commercial/basic-demo.json` (prefix `PVLab`)
- **Minimal/focused**: `configs/commercial/dlp-only.json`
- **Integrated AI governance**: `configs/commercial/ai-demo.json` (prefix `PVAI`, includes Sentinel)
- **Sentinel-only**: `configs/commercial/purview-sentinel-demo.json` (prefix `PVSentinel`)

## Smoke test

After creating the config, validate with a dry run:
```powershell
./Deploy-Lab.ps1 -ConfigPath configs/<cloud>/<name>.json -Cloud <cloud> -SkipAuth -WhatIf
```
