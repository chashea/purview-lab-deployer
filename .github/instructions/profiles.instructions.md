---
applyTo: "profiles/**"
---

# Profile and Capability Rules

- Capability profiles at `profiles/<cloud>/capabilities.json` control deployment gating.
- Workload statuses: `available` (fully supported), `limited` (functional, feature gaps), `delayed` (not yet rolled out), `unavailable` (blocked).
- Deploy blocks on `unavailable` workloads. Remove warns but does not block.
- When adding a new workload, update capability profiles for both `commercial` and `gcc`.
- Deployment profile directories (e.g., `profiles/commercial/basic/`) contain README, talk tracks, runbooks, and demo scenarios.
- The `ai` profile has a manual demo runbook at `profiles/commercial/ai/RUNBOOK.md`.
