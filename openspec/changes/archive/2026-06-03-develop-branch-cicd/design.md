# Design: Agregar rama `develop` y modificar CI/CD

## Technical Approach

Single-job workflow modification with conditional apply. `deploy.yml` gains `pull_request` trigger for plan-only validation and expands `push` trigger to include `develop`. No Terraform backend changes — shared `etl-earthquake-azure.tfstate` key per user's explicit choice. Terraform's native state lock prevents concurrent applies.

## Architecture Decisions

| Decision | Choice | Rejected | Rationale |
|----------|--------|----------|-----------|
| State isolation | Shared key for both branches | Separate keys per branch (exploration rec) | User explicitly chose shared: "es algo personal y sencillo." Single dev, terraform lock is sufficient. |
| Job structure | Single job, conditional apply step | Two jobs (plan + apply with artifact passing) | 58-line workflow. Over-engineering a two-job structure adds artifact upload/download complexity for zero gain in a personal project. |
| PR trigger filtering | Same path filters as push (`terraform/**`, `databricks/**`) | No path filter (validate everything) | Consistency with push trigger. PRs that don't touch infra shouldn't trigger a terraform plan. |

## CI/CD Trigger Flow

```
                  ┌────────────────────────────────────────┐
                  │            GitHub Events                │
                  └──────┬──────────────────┬──────────────┘
                         │                  │
                    push to            pull_request to
                  main|develop         main|develop
                         │                  │
                         ▼                  ▼
                  ┌──────────────┐   ┌──────────────┐
                  │  terraform   │   │  terraform   │
                  │  fmt         │   │  fmt         │
                  │  init        │   │  init        │
                  │  validate    │   │  validate    │
                  │  plan        │   │  plan        │
                  │  apply  ◄────│───│  (skip apply)│
                  └──────────────┘   └──────────────┘
                    if: push event       if: pr event
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `.github/workflows/deploy.yml` | Modify | Expand `push.branches` to `[main, develop]`. Add `pull_request` trigger with same paths. Gate apply step behind `github.event_name == 'push'`. Rename job to "Terraform Plan & Apply." |
| `DEPLOY.md` | Modify | Replace "push a main" with two-branch model. Add branch strategy section. Update CI/CD section 4.2. Update ASCII diagram. |

## deploy.yml Diff (Logical)

```yaml
on:
  push:
    branches: [main, develop]        # ← expanded
    paths: ["terraform/**", "databricks/**"]
  pull_request:                      # ← new trigger
    branches: [main, develop]
    paths: ["terraform/**", "databricks/**"]
  workflow_dispatch:

jobs:
  terraform:
    name: Terraform Plan & Apply     # ← renamed
    # ... all steps unchanged until apply ...

    - name: Terraform Apply
      if: github.event_name == 'push'  # ← gate
      run: terraform apply tfplan
```

## Branch Strategy

```
feature/* ──PR──▶ develop ──PR──▶ main
                      │              │
                      ▼              ▼
                 push = apply    push = apply
                 PR   = plan     PR   = plan
```

- **develop**: Integration branch. Push triggers full deploy (apply). PRs run plan-only.
- **main**: Stable/production. Same behavior — push applies, PR plans.
- **Feature branches**: Branch off `develop`. PR into `develop` triggers plan validation.
- **Merging develop → main**: PR triggers plan. Review it. Merge. Push to main triggers apply.

## DEPLOY.md Changes

| Section | Change |
|---------|--------|
| New section after intro | "Estrategia de ramas" — explica `feature → develop → main`, cuándo pushear a cada una |
| 4.2 Desde CI/CD | Agregar `git push origin develop` como alternativa. Explicar que ambas ramas deployan. |
| 6.6 Conectar Git (ADF) | Nota: ADF permanece conectado a `main` (los notebooks en Databricks no cambian con la rama de ADF) |
| Diagrama ASCII final | Actualizar "Push a main" → "Push a main o develop" |

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Manual — push to develop | CI ejecuta fmt→init→validate→plan→apply | Push un cambio trivial a `terraform/` en develop, verificar CI pasa |
| Manual — PR plan-only | CI ejecuta fmt→init→validate→plan (sin apply) | Crear PR develop→main, verificar que apply NO se ejecuta |
| Manual — push to main | CI sigue funcionando igual que antes | Push a main con cambio en terraform/**, verificar apply |
| Regression | `workflow_dispatch` sigue funcionando | Disparar manualmente desde GitHub Actions UI |

No automated test framework exists in this project (`test_command: ""` in config).

## Migration / Rollout

No migration required. Rollback: delete `develop` branch remotely, revert `deploy.yml` to single-branch trigger, revert `DEPLOY.md`.

## Open Questions

None. Scope is fully bounded: ~10 lines of workflow YAML, branch creation, DEPLOY.md update.
