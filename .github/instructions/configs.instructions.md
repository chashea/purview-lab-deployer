---
applyTo: "configs/**"
---

# Config File Rules

- Config files are cloud-scoped: `configs/commercial/*.json` or `configs/gcc/*.json` only. Never create root-level configs.
- Required fields: `labName`, `prefix`, `domain`. Optional: `cloud` (commercial/gcc).
- Workloads are toggled via `"enabled": true/false` in the `workloads` object.
- Validate against the canonical schema at `configs/_schema.json`.
- Before enabling a workload, check `profiles/<cloud>/capabilities.json` for availability status.
- Baseline labs use prefix `PVLab`. Shadow AI uses prefix `PVShadowAI`.
- File naming convention: `<scenario>-demo.json`.
- DLP rules reference built-in Microsoft SITs by exact name (e.g., `U.S. Social Security Number (SSN)`, `Credit Card Number`).
