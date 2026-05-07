> # ⚠️ This repository is DEPRECATED — split into two single-cloud successor repos
>
> | Cloud | Successor repo | Status |
> |---|---|---|
> | Microsoft 365 (Commercial) | [`chashea/purview-lab-deployer-commercial`](https://github.com/chashea/purview-lab-deployer-commercial) | active |
> | Microsoft 365 GCC (US Government Community) | [`chashea/purview-lab-deployer-gcc`](https://github.com/chashea/purview-lab-deployer-gcc) | active |
>
> This repo will receive **no further updates**. New work — bug fixes, new
> profiles, schema changes, workflow updates — happens in the per-cloud repos
> only. Re-clone whichever variant matches the tenant you target.
>
> Why the split:
> - Each per-cloud repo is simpler than this monorepo (no multi-cloud
>   parameterization, no dead branches, single config tree at `configs/`).
> - Independent release cycles per cloud — commercial DLP/IRM features can
>   ship the day they GA without waiting on GCC parity.
> - Per-cloud workflows and OIDC subjects, no per-cloud matrix fan-out.
>
> History is preserved in both successor repos via `git filter-repo`. Your old
> issues, PRs, and discussions remain here for reference but won't be acted on
> — please open new ones in the per-cloud repo that matches your tenant.
>
> The repo is **not archived** so the existing GitHub Actions runs and links
> to specific commits stay live. Treat it as read-only.

---

# purview-lab-deployer (deprecated, multi-cloud monorepo)

The legacy multi-cloud Microsoft Purview demo lab deployer. PowerShell 7+,
modular by workload, deploy/teardown symmetric, supported both Commercial and
GCC tenants via cloud-scoped subdirs (`configs/commercial/`, `configs/gcc/`,
`profiles/commercial/`, `profiles/gcc/`).

The full feature set, profile catalog, workflow setup, and contribution guide
live in the successor repos linked above. Both v5.0.0 releases are direct
descendants of v4.6.0 of this repo, with the structural split as the only
breaking change. Any prior usage of `-Cloud commercial` or `-Cloud gcc`
becomes implicit when you switch to the matching successor repo.

## Migration

1. Pick the successor repo for your tenant (Commercial or GCC).
2. Re-clone:
   ```bash
   # Commercial
   git clone https://github.com/chashea/purview-lab-deployer-commercial.git
   # GCC
   git clone https://github.com/chashea/purview-lab-deployer-gcc.git
   ```
3. The `configs/<cloud>/<name>.json` you used here lives at `configs/<name>.json`
   in the successor (e.g. `configs/commercial/ai-demo.json` →
   `configs/ai-demo.json` in the commercial repo).
4. Drop `-Cloud commercial` / `-Cloud gcc` from any deploy invocations — the
   successor repos are pinned per-cloud and the parameter is back-compat-only.
5. If you have a CI/CD federated credential pointing at this repo, update the
   subject to `repo:chashea/purview-lab-deployer-commercial:environment:commercial`
   or `repo:chashea/purview-lab-deployer-gcc:environment:gcc` as appropriate.

## License & history

Same MIT license as before. Commit history through v4.6.0 is preserved in
both successor repos (drop-and-rename via `git filter-repo`), so `git blame`
on inherited code still shows the original authors.
