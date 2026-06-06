# Tasks: Agregar rama `develop` y modificar CI/CD

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 30–40 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

Not needed — single PR well under 400-line budget.

## Phase 1: CI/CD Workflow

- [x] 1.1 Expand `on.push.branches` to `[main, develop]` in `.github/workflows/deploy.yml`
- [x] 1.2 Add `pull_request` trigger with branches `[main, develop]` and same path filters
- [x] 1.3 Gate Terraform Apply step with `if: github.event_name == 'push'`
- [x] 1.4 Rename job from "Terraform Apply" to "Terraform Plan & Apply"

## Phase 2: Branch Creation

- [x] 2.1 Create `develop` from `main` locally and push: `git checkout -b develop main && git push origin develop`

## Phase 3: Documentation

> **Intencionalmente omitido**: DEPLOY.md fue removido de los commits por decisión del usuario. Las tareas 3.1–3.4 no aplican.

- [-] 3.1 Add "Estrategia de ramas" section to `DEPLOY.md` after intro explaining `feature → develop → main` flow
- [-] 3.2 Update section 4.2 (Desde CI/CD) with `git push origin develop` as alternative
- [-] 3.3 Add ADF note in 6.6: ADF stays connected to `main`
- [-] 3.4 Update ASCII diagram footer from "Push a main" to "Push a main o develop"

## Phase 4: Verification

- [x] 4.1 Validate `deploy.yml` is valid YAML (`yamllint .github/workflows/deploy.yml`)
- [x] 4.2 Run `terraform validate` from root to confirm no breakage
- [ ] 4.3 Manual: push a trivial change to `terraform/` on `develop` → verify CI runs apply
- [ ] 4.4 Manual: open PR `develop`→`main` → verify CI runs plan only (no apply)
- [ ] 4.5 Manual: push to `main` → verify CI still runs apply as before
- [ ] 4.6 Manual: trigger `workflow_dispatch` → verify it still works
