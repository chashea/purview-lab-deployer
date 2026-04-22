---
name: validate-config
description: Validate a config JSON against schema + delegate DLP preflight checks. Run BEFORE Deploy-Lab.
user_invocable: true
---

Validate a Purview lab config without deploying.

## Steps

1. **Resolve path** — `$ARGUMENTS` should be a path under `configs/<cloud>/`. If empty, list available configs and prompt.
2. **Schema check** — validate the JSON against `configs/_schema.json`. Report missing required fields (`labName`, `prefix`, `domain`).
3. **Workload toggle sanity** — list which workloads are `enabled: true`; flag combinations that don't make sense (e.g., DLP enabled but SensitivityLabels disabled when DLP rules reference labels).
4. **Capability gate** — load `profiles/<cloud>/capabilities.json`; flag enabled workloads that are `unavailable` for that cloud.
5. **Delegate DLP preflight** — invoke the `dlp-preflight-validator` agent on the config. Report its findings inline.
6. **Prefix collision** — quick scan of recent manifests under `manifests/<cloud>/` for the same prefix; warn if reused.

## Output

- Pass / fail
- Schema errors (with JSON path)
- DLP preflight summary
- Prefix collisions
- Recommended next command (`/deploy` or fix-then-revalidate)

Never modify the config — only report.
