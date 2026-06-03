## Exploration: ADF Objects via Code

### Current State

El proyecto define la infraestructura base de Azure Data Factory en `terraform/datafactory.tf` mediante `azurerm_data_factory` — pero **NO crea ningún objeto interno de ADF (pipelines, linked services, datasets, triggers) mediante código**. Todo se crea manualmente en ADF Studio.

El archivo `plan.md` lo dice explícitamente:
- *"ADF Linked Services se crean desde Studio (no via código)"*
- *"ADF pipelines — los creás en Studio con Copy Data + 2 Databricks Notebook steps + Trigger"*

**Lo que existe hoy en Terraform (`datafactory.tf`):**
- `azurerm_data_factory.main` — el recurso ADF vacío
- `azurerm_role_assignment.adf_to_storage` — Managed Identity del ADF tiene `Storage Blob Data Contributor` sobre ADLS
- `azurerm_role_assignment.adf_to_databricks` — Managed Identity del ADF tiene `Contributor` sobre Databricks workspace

**Lo que se crea manualmente hoy en ADF Studio (según README.md):**
1. Linked Service a ADLS (Managed Identity)
2. Linked Service a Databricks (PAT token)
3. Pipeline `PL_MasterPipeline`:
   - Copy Data (HTTP USGS → ADLS bronze/)
   - Databricks Notebook (01_bronze_to_silver)
   - Databricks Notebook (02_silver_to_gold)
4. Trigger Schedule cada 6h
5. Conexión Git al repositorio

### Affected Areas

- `terraform/datafactory.tf` — lugar principal donde se agregarían los nuevos recursos ADF
- `terraform/variables.tf` —可能需要新变量（Databricks workspace URL, cluster ID, etc.）
- `terraform/outputs.tf` —可能需要新 outputs
- `terraform/databricks.tf` — el ID del cluster job existente puede referenciarse desde los linked services
- `.github/workflows/deploy.yml` — potencialmente, si se necesita un paso post-terraform para ADF
- `plan.md` — actualizar para reflejar que ADF objects ya no son manuales
- `README.md` — actualizar la sección "Configuración post-deploy"

### Approaches

#### 1. **Terraform nativo (`azurerm_data_factory_*` resources)**

Usar los recursos del provider `azurerm` para definir linked services, datasets, pipeline y trigger como recursos HCL.

**Recursos necesarios:**
- `azurerm_data_factory_linked_service_web` — Linked Service HTTP para USGS API
- `azurerm_data_factory_linked_service_azure_blob_storage` — Linked Service a ADLS (con Managed Identity)
- `azurerm_data_factory_linked_service_azure_databricks` — Linked Service a Databricks (con `msi_workspace_id`, no PAT)
- `azurerm_data_factory_dataset_http` — Dataset del CSV de USGS
- `azurerm_data_factory_dataset_delimited_text` — Dataset del destino en ADLS bronze
- `azurerm_data_factory_pipeline` — Pipeline con `activities_json`
- `azurerm_data_factory_trigger_schedule` — Trigger cada 6h

**Pros:**
- Mismo tooling que el resto del proyecto (un solo `terraform apply`)
- Estado manejado por Terraform state
- ADF Managed Identity sirve para auth tanto a ADLS como a Databricks (sin PAT token)
- CI/CD existente lo deploya automáticamente

**Cons:**
- `activities_json` del pipeline es JSON plano — no hay validación HCL de la estructura interna
- Las actividades Copy Data y Databricks Notebook tienen JSON complejo
- Cambios en activities_json no se benefician del diff semántico de Terraform (sabe que cambió pero no qué cambió adentro)

**Effort:** Medium

#### 2. **ARM templates deployados por Terraform**

Definir los objetos ADF como plantillas ARM (JSON) y deployarlos mediante `azurerm_resource_group_template_deployment`.

**Pros:**
- ARM es el formato nativo de ADF — exportable desde Studio
- Se puede empezar creando los objetos en Studio, exportando el ARM y luego subiéndolo a código
- Más fácil de auditar para quienes conocen ADF ARM

**Cons:**
- Introduce un segundo mecanismo de deploy al proyecto
- ARM templates son verbosos
- `azurerm_resource_group_template_deployment` no maneja estado incremental bien — puede causar problemas en updates
- Dependencia de orden: primero Terraform, luego ARM

**Effort:** High

#### 3. **Azure CLI / PowerShell en CI/CD**

Agregar steps en `.github/workflows/deploy.yml` que ejecuten comandos `az datafactory` o cmdlets `Az.DataFactory` después de `terraform apply`.

**Pros:**
- Fácil de prototipar
- Se pueden usar comandos imperativos para todo
- No requiere cambios en Terraform

**Cons:**
- Estado imperativo — no hay idempotencia garantizada
- GitHub Actions tendría que manejar lógica de "crear o actualizar"
- Rompe el patrón IaC del proyecto
- Más difícil de revisar y mantener
- El SP necesita permisos `Data Factory Contributor` en el ADF

**Effort:** Low (pero frágil)

#### 4. **ADF DevOps (npm @microsoft/azure-data-factory-utilities)**

Usar las herramientas ADF DevOps (ADF Utilities npm package) para validar y publicar ARM desde el repo en CI/CD.

**Pros:**
- Alineado con el flujo "ADF Git integration" nativo
- Puedes editar pipelines en ADF Studio y commitear a Git, y CI/CD publica

**Cons:**
- Requiere setup inicial de Git integration en ADF Studio
- Dependencia de Node.js en CI/CD
- El proyecto no tiene Node.js tooling actualmente
- Más moving parts

**Effort:** High

### Recommendation

**Enfoque 1 (Terraform nativo)** — es la opción correcta para este proyecto.

Razones:
1. El proyecto **ya es Terraform-centric**. Todo el resto de la infraestructura se maneja con Terraform. Agregar linked services, datasets, pipeline y trigger como `azurerm_data_factory_*` resources mantiene la consistencia.
2. El ADF tiene **Managed Identity** con roles asignados (Storage Blob Data Contributor + Contributor en Databricks). El linked service de Databricks puede usar `msi_workspace_id` en lugar de PAT token — eliminando la dependencia de `DATABRICKS_TOKEN` para ADF.
3. La CI/CD existente ya ejecuta `terraform apply` — estos recursos nuevos se deployarían automáticamente.
4. El pipeline es relativamente simple (Copy Data + 2 Notebook activities), el JSON de `activities_json` es manejable.

**Patrón concreto propuesto:**

```
terraform/datafactory.tf
├── resource "azurerm_data_factory" "main"           ← YA EXISTE
├── resource "azurerm_role_assignment" * 2           ← YA EXISTE
├── resource "azurerm_data_factory_linked_service_web"        → USGS HTTP
├── resource "azurerm_data_factory_linked_service_azure_blob_storage" → ADLS (Managed Identity)
├── resource "azurerm_data_factory_linked_service_azure_databricks"   → Databricks (MSI)
├── resource "azurerm_data_factory_dataset_http"              → USGS CSV source
├── resource "azurerm_data_factory_dataset_delimited_text"    → Bronze sink
├── resource "azurerm_data_factory_pipeline"                  → PL_MasterPipeline
└── resource "azurerm_data_factory_trigger_schedule"          → Cada 6h
```

**Consideraciones de implementación:**
- El linked service de ADLS usa `use_managed_identity = true` — ya tiene el RBAC asignado
- El linked service de Databricks usa `msi_workspace_id` apuntando al workspace ID de Databricks — ya tiene Contributor role
- Para el pipeline, se necesita la URL del workspace de Databricks (disponible como output de `azurerm_databricks_workspace.main.workspace_url`) y el ID del cluster job (`databricks_cluster.job_cluster.id`)
- `variables.tf` necesita una variable para `databricks_workspace_id` (el workspace resource ID, que ya se usa en unity_catalog.tf)
- El `activities_json` del pipeline debe modelar: (1) Copy Data con source HTTP y sink ADLS delimited text, (2) Notebook 01_bronze_to_silver, (3) Notebook 02_silver_to_gold — con dependencias secuenciales

### Estructura de archivos resultante

```
terraform/
├── datafactory.tf       ← MODIFICADO: se agregan ~7 nuevos resources
├── variables.tf          ← MODIFICADO: se agrega databricks_workspace_id
├── databricks.tf         ← POSIBLEMENTE referenciado (cluster id)
├── outputs.tf            ← POSIBLEMENTE nuevos outputs (pipeline name, trigger id)
README.md                 ← ACTUALIZAR sección post-deploy
plan.md                   ← ACTUALIZAR: ya no son manuales
openspec/changes/adf-objects-via-code/   ← directorio de cambio activo
```

### Gaps y blockers

1. **No hay variable `databricks_workspace_id`** — `unity_catalog.tf` calcula el access connector ID con un local usando `data.azurerm_client_config.current.subscription_id`, pero no expone un ID de workspace usable para el linked service de Databricks. Se necesita agregar una variable o un data source.
2. **El cluster de Databricks es un `databricks_cluster` resource** — su ID se puede referenciar desde el linked service como `existing_cluster_id` o se puede configurar `new_cluster_config` en su lugar.
3. **Activities JSON es frágil** — el JSON del pipeline debe construirse manualmente. Conviene documentar la estructura de cada actividad.
4. **Trigger schedule** — requiere `pipeline_name` y opcionalmente `pipeline_parameters`. El pipeline se deploya con el mismo `terraform apply`, así que el trigger puede referenciarlo directamente.

### Ready for Proposal

**Yes** — el análisis está completo. Tengo claros el alcance, las opciones y la recomendación. El siguiente paso es `sdd-propose` para formalizar el approach y el scope del cambio.
