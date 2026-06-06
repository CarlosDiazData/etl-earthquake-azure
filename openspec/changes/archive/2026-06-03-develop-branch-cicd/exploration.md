## Exploration: Git Flow — Agregar rama `develop` y CI/CD para ambas ramas

### Current State

- **Ramas**: Solo existe `main` (local y remota/origin). No hay `develop`.
- **CI/CD**: Un único workflow `.github/workflows/deploy.yml` (58 líneas) que se dispara con `push` a `main` cuando se modifican `terraform/**` o `databricks/**`. Ejecuta `terraform validate → plan → apply` contra `dev.tfvars`.
- **Estado de Terraform**: Usa backend `azurerm` con un solo archivo `etl-earthquake-azure.tfstate`. No hay separación por entorno ni por rama.
- **Entornos**: Solo existe un entorno "dev" (definido en `terraform/dev.tfvars` y en variables de Terraform con `environment = "dev"`).
- **No hay PR triggers**: El workflow solo escucha `push` directo a `main`. No hay `pull_request` events.
- **ADF Git config**: El DEPLOY.md menciona que ADF está conectado a la rama `main`.

### Affected Areas

- **`.github/workflows/deploy.yml`** — Es el único archivo CI/CD. Hay que modificar los triggers para incluir `develop` y posiblemente agregar comportamiento diferencial por rama.
- **`terraform/main.tf`** — El backend block define un solo `key` fijo: `etl-earthquake-azure.tfstate`. Si ambas ramas deployan, van a competir por el mismo estado.
- **`terraform/dev.tfvars`** — Actualmente único var-file. Si `develop` y `main` deployan con distintos var-files, habrá que crear uno adicional.
- **`DEPLOY.md`** — Documentación que referencia `git push origin main` como mecanismo de deploy.
- **No hay otros workflows ni scripts de CI/CD.**

### Approaches

1. **Un solo tfstate compartido + branch protection**
   - El workflow se modifica para aceptar pushes a `develop` Y a `main`, ambos usando el mismo backend key y el mismo `dev.tfvars`.
   - Se agrega un job `plan-only` para PRs dirigidos a `develop`/`main`.
   - Pros: Mínimo cambio de infraestructura (~10 líneas modificadas en el workflow).
   - Cons: **PELIGROSO** — dos branches haciendo `apply` simultáneo sobre el mismo tfstate pueden corromperlo. Terraform locks ayudan pero no eliminan el riesgo de conflictos de estado.
   - Effort: Bajo

2. **Separación de estado por rama (backend key dinámico)**
   - El workflow determina el backend key según la rama: `etl-earthquake-azure-main.tfstate` vs `etl-earthquake-azure-develop.tfstate`.
   - Se agrega un job `plan-only` para PRs, y `apply` solo en push directo a `develop`/`main`.
   - Pros: Aislación completa de estado. Se puede deployar `develop` sin afectar `main`.
   - Cons: Dos archivos de estado que mantener. Si después se quiere agregar un entorno "prod" en `main`, se necesitará un var-file adicional.
   - Effort: Medio (~15-20 líneas modificadas en el workflow)

3. **Git Flow completo (develop → dev, main → prod, dos var-files)**
   - `develop` usa `dev.tfvars` y backend key con sufijo `-develop`.
   - `main` usa `prod.tfvars` (a crear) y backend key con sufijo `-main`.
   - Se agrega pipeline de plan-only para PRs, apply solo en push a cada rama.
   - Pros: Arquitectura preparada para producción. Madura y testeada.
   - Cons: Requiere crear `prod.tfvars` y asegurar que los secrets de GitHub sirvan para ambos entornos. Más esfuerzo inicial. El proyecto actualmente solo tiene un entorno dev.
   - Effort: Alto (~30-40 líneas + nuevo var-file)

### Recommendation

**Opción 2 — Separación de estado por rama**. Es el paso evolutivo lógico:
- El proyecto tiene un solo entorno (dev), así que Opción 3 es over-engineering.
- Opción 1 es riesgosa: compartir tfstate entre ramas va a causar dolor eventualmente.
- Con Opción 2, ambas ramas deployan al mismo entorno Azure (dev) pero con estado aislado. Cuando en el futuro se agregue un entorno prod, la migración a Opción 3 es trivial.

### Cambios específicos necesarios

En el workflow `deploy.yml`:
1. Agregar `develop` al trigger `push.branches` (junto con `main`)
2. Agregar trigger `pull_request` para plan-only
3. Extraer el backend key a una variable basada en `github.ref_name`:
   - `main` → `etl-earthquake-azure-main.tfstate`
   - `develop` → `etl-earthquake-azure-develop.tfstate`
4. Agregar un job `plan-only` que corra en PRs (sin apply)
5. Que el job de apply solo corra en `push` directo (no en PR)

En git:
1. Crear rama `develop` desde `main`
2. Pushear `develop` al remoto
3. Configurar branch protection rules en GitHub para `develop` y `main`

### Risks

- **Estado duplicado**: Si se deploya `develop` y después se mergea a `main`, el apply de `main` va a recrear recursos que ya existen (depende de cómo Terraform maneje el drift). Es esperado y manejable.
- **Secrets compartidos**: Las GitHub Actions secrets (`ARM_CLIENT_ID`, etc.) son las mismas para ambas ramas. El Service Principal deploya sobre la misma suscripción. Si se quiere aislar entornos después, habrá que crear un segundo SP.
- **ADF Git config**: El DEPLOY.md menciona que ADF está conectado a `main`. Si se quiere que ADF también use `develop`, habrá que reconfigurarlo manualmente en el portal.
- **Databricks token único**: `DATABRICKS_TOKEN` es compartido. No hay riesgo inmediato porque apunta al mismo workspace.
- **PRs desde develop**: Si alguien crea un PR de `develop` a `main`, y ambos ya deployaron, el PR de código no debería tener conflictos de infraestructura porque los estados están separados.

### Ready for Proposal

Sí. El alcance está claro y delimitado:
1. Crear rama `develop`
2. Modificar `deploy.yml` para soportar ambas ramas con estado aislado
3. Agregar plan-only en PRs
4. Actualizar `DEPLOY.md` para reflejar el nuevo flujo

Se puede proceder directamente a `sdd-propose`.
