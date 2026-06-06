# Proposal: Agregar rama `develop` y modificar CI/CD para ambas ramas

## Intent

El proyecto solo tiene `main`. Cualquier cambio de infra requiere push directo sin validación previa. Se necesita `develop` como rama de integración, manteniendo `main` como canal estable.

## Scope

### In Scope
- Crear rama `develop` desde `main`, pushear a remoto
- Modificar `.github/workflows/deploy.yml`: agregar `develop` a `push.branches` y trigger `pull_request` para plan-only en `main` y `develop`
- Actualizar `DEPLOY.md` con la estrategia de dos ramas

### Out of Scope
- Separación de tfstate por rama (backend key dinámico)
- Var-files adicionales (se mantiene solo `dev.tfvars`)
- Nuevos entornos Azure ni reconfiguración de ADF Git
- Branch protection rules (se agregan manualmente si se desea)

## Capabilities

### New Capabilities
None — cambio puramente de CI/CD workflow.

### Modified Capabilities
None — no hay specs existentes afectadas.

## Approach

**Approach 1 — shared tfstate** (elección del usuario: "es algo personal y sencillo"). Ambas ramas comparten backend key `etl-earthquake-azure.tfstate` y `dev.tfvars`. Solo se modifican triggers (~10 líneas). El lock nativo de Terraform previene apply concurrente.

Workflow resultante:
| Evento | Ramas | Acción |
|--------|-------|--------|
| `push` (terraform/**, databricks/**) | `main`, `develop` | fmt → init → validate → plan → apply |
| `pull_request` | `main`, `develop` | fmt → init → validate → plan (sin apply) |

## Affected Areas

| Area | Impact |
|------|--------|
| `.github/workflows/deploy.yml` | Modified — triggers ampliados + `pull_request` event |
| Rama `develop` | New — creada desde `main` |
| `DEPLOY.md` | Modified — documentar flujo con dos ramas |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Conflicto de tfstate (apply simultáneo) | Low | Lock de Terraform. Un solo dev. |
| Drift post-merge `develop` → `main` | Low | `terraform plan` en el PR lo detecta antes del apply. |
| Plan en PR refleja estado modificado por `develop` | Medium | Esperado. Se revisa manualmente antes de mergear. |

## Rollback Plan

1. `git branch -d develop && git push origin --delete develop`
2. Revertir `deploy.yml` a trigger original (`push.branches: [main]`, sin `pull_request`)
3. Revertir cambios en `DEPLOY.md`
4. Si hay inconsistencia en Azure: `terraform apply -var-file=dev.tfvars` desde `main`

## Dependencies

Ninguna. No se requieren nuevos secrets, SPs, ni recursos Azure.

## Success Criteria

- [ ] `git branch -a` muestra `remotes/origin/develop`
- [ ] Push a `develop` con cambios en `terraform/**` dispara `terraform validate → plan → apply`
- [ ] PR `develop` → `main` dispara plan sin apply
- [ ] Push a `main` sigue funcionando igual
- [ ] `DEPLOY.md` documenta `develop` y cuándo usarla
