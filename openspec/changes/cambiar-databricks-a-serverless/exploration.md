## Exploration: Migrar Azure Databricks de Clusters Clásicos a Serverless

### Current State

El proyecto `etl-earthquake-azure` usa Azure Databricks con un **cluster clásico persistente** (`databricks_cluster.job_cluster`) de tipo job, con `Standard_DS3_v2` (1 worker, 30 min autotermination). Este cluster se referencia desde:

1. **ADF Linked Service** (`azurerm_data_factory_linked_service_azure_databricks.databricks`) vía `existing_cluster_id = databricks_cluster.job_cluster.id` — esto hace que ADF ejecute notebooks directamente sobre ese cluster.
2. El cluster tiene **Spark conf OAuth** hardcodeado para acceder a ADLS Gen2 con el Service Principal (`azure_client_id`, `azure_client_secret`).

Además, existe **Unity Catalog** con storage credentials y external locations para bronze/silver/gold, y los notebooks usan rutas `abfss://` para leer/escribir en ADLS.

**Lo que NO existe:** `databricks_sql_endpoint`, `databricks_job` resources, ni ningún recurso serverless.

### Affected Areas

| Archivo | Por qué se ve afectado |
|---------|----------------------|
| `terraform/databricks.tf` | Contiene `databricks_cluster.job_cluster`, los data sources `databricks_node_type` y `databricks_spark_version`, y el Spark conf OAuth. Todo esto cambia o se elimina. |
| `terraform/datafactory.tf` | Línea 62: `existing_cluster_id = databricks_cluster.job_cluster.id` — referencia directa al cluster clásico. El linked service debe cambiar. |
| `terraform/unity_catalog.tf` | Los external locations ya existen, pero al migrar a serverless la autenticación con ADLS cambia (Managed Identity del workspace en vez de OAuth del SP). |
| `terraform/main.tf` | Provider de Databricks — la autenticación vía Azure SP podría simplificarse si se usa solo Unity Catalog + access connector. |
| `terraform/variables.tf` | `azure_client_id`, `azure_client_secret`, `azure_tenant_id` podrían ya no ser necesarios para Databricks si se elimina el Spark conf OAuth. |
| `terraform/outputs.tf` | Outputs del workspace se mantienen. |
| `databricks/01_bronze_to_silver.py` | No requiere cambios de lógica — las rutas `abfss://` funcionan igual. Pero la autenticación podría cambiar de OAuth (Spark conf) a Managed Identity (Unity Catalog). |
| `databricks/02_silver_to_gold.py` | Idem: sin cambios de lógica, pero el método de autenticación cambia. |
| `.github/workflows/deploy.yml` | Las variables `TF_VAR_azure_client_secret` podrían dejar de ser necesarias para Databricks si se elimina el Spark conf. |
| `openspec/specs/adf-linked-services/spec.md` | Especificación actual exige `existing_cluster_id` — debe actualizarse para serverless/per-job cluster. |
| `openspec/specs/adf-pipeline-orchestration/spec.md` | Hace referencia a notebooks ejecutándose en Databricks — la orquestación podría migrar a Databricks Jobs. |

### Conceptos Clave de Serverless en Azure Databricks

**1. Serverless SQL Warehouses**
- Recurso: `databricks_sql_endpoint` con `enable_serverless_compute = true`
- Para consultas SQL y BI, no aplica a los notebooks PySpark del ETL.
- Es un feature adicional, no un reemplazo para los notebooks.

**2. Serverless para Jobs/Notebooks (en Azure)**
- NO existe un recurso Terraform "serverless compute" directo para notebooks en Azure.
- El `azurerm_databricks_workspace` NO tiene una propiedad `compute_mode = "SERVERLESS"` (eso solo existe para AWS/GCP vía `databricks_mws_workspaces`).
- En Azure, serverless para jobs se habilita **desde la UI del workspace** (Settings → Serverless Compute → Enable) una vez que el workspace es `premium` y está en una región soportada.
- Una vez habilitado, los jobs pueden usar serverless compute. ADF puede ejecutarlos nativamente vía `AzureDatabricksJob` activity (ver sección 4).

**3. Opciones de ADF Linked Service para Databricks**
- `existing_cluster_id` — usa un cluster clásico ya existente (enfoque actual).
- `new_cluster_config` — crea un cluster efímero por ejecución (sigue siendo classic compute, pero no persistente).
- `instance_pool` — usa un instance pool.

**4. ADF Job Activity (descubrimiento clave — Jun 2026)**

La documentación oficial de Microsoft confirma que ADF tiene una actividad nativa `AzureDatabricksJob` que **ejecuta serverless automáticamente**:

> *"The Azure Databricks Job Activity automatically runs on serverless clusters, so you don't need to specify a cluster in your linked service configuration."*

— [Transform data by running a Databricks job](https://learn.microsoft.com/azure/data-factory/transform-data-databricks-job)

Propiedades de la Job Activity:
```json
{
    "type": "AzureDatabricksJob",
    "linkedServiceName": "DatabricksLinkedService",
    "jobId": "123456",
    "jobParameters": { "param1": "value1" }
}
```

**Implicaciones**:
- El linked service de ADF **no necesita configuración de cluster** (`existing_cluster_id`, `new_cluster_config`, etc.) — solo workspace URL + autenticación.
- Se selecciona "Serverless" en la UI de la actividad o vía JSON.
- No se necesita Web Activity ni llamadas manuales a la API de Databricks — es **nativo de ADF**.
- Esto elimina la complejidad del "enfoque híbrido" que requería Web Activities.

**5. Autenticación con ADLS**
- Actual: OAuth vía Spark conf con client_id/client_secret en el cluster clásico.
- Serverless/UC: Unity Catalog + Managed Identity del workspace (via `databricks_access_connector`). Ya existe `databricks_storage_credential` pero los notebooks no lo usan — siguen usando Spark conf OAuth.

### Approaches

**1. ADF + New Cluster Config (Per-Job Cluster Efímero)**
Reemplazar `existing_cluster_id` por `new_cluster_config` en el ADF Linked Service y eliminar `databricks_cluster`.
- **Pros**: Cambio mínimo, no requiere re-arquitectura. Elimina el cluster persistente.
- **Cons**: NO es serverless — classic compute efímero (aprovisiona VMs por ejecución). Cold start 3-5 min. Aún requiere Spark conf OAuth.
- **Esfuerzo**: Low

**2. ADF Job Activity + Databricks Jobs Serverless (✅ RECOMENDADO)**
Crear `databricks_job` resources en Terraform (uno por notebook). ADF usa la actividad nativa `AzureDatabricksJob` que ejecuta serverless automáticamente — sin configuración de cluster en el linked service.
- **Pros**: Serverless real. Sin cluster management. Startup < 10s. Sin Web Activity ni API calls manuales. Nativo de ADF. Migración gradual posible.
- **Cons**: Los notebooks deben migrar de ABFSS directo a Unity Catalog (no hay Spark conf). Habilitación serverless es manual.
- **Esfuerzo**: Low-Medium

**3. Databricks Workflows (sin ADF)**
Migrar toda la orquestación a Databricks Workflows: `databricks_job` con múltiples tareas (bronze→silver, silver→gold), schedule nativo, eliminar ADF pipeline/trigger.
- **Pros**: Control total desde Databricks. Sin dependencia de ADF.
- **Cons**: Se pierde la UI unificada de ADF. Monitoring y metadatos cambian. Breaking change arquitectónico.
- **Esfuerzo**: High

### Análisis Técnico Detallado

**Autenticación con ADLS (cambio crítico)**

Actualmente los notebooks usan:
```python
ABFSS_PATH = f"abfss://container@account.dfs.core.windows.net/path"
# La autenticación OAuth viene del Spark conf del cluster
```

Con serverless + Unity Catalog, los notebooks DEBEN usar las rutas de external locations en vez de ABFSS directo, o usar un mount point. El Spark conf OAuth ya no existe porque serverless no tiene Spark conf.

Unity Catalog ya está configurado con:
- `databricks_storage_credential.main` — Managed Identity del access connector
- `databricks_external_location.{bronze,silver,gold}` — rutas ABFSS por container

Pero los notebooks NO usan estas external locations — escriben ABFSS directamente. Para migrar a serverless, los notebooks deben cambiar a rutas de UC:
```python
# En vez de:
df.write.format("delta").save("abfss://silver@account.dfs.core.windows.net/cleansed/")

# Usar:
spark.sql("CREATE OR REPLACE TABLE silver.earthquake_events ... LOCATION 'el-earthquake-silver/cleansed/'")
```

Otra alternativa: crear mount points vía `databricks_mount` (no recomendado con UC).

**Riesgo: Serverless no soporta Spark conf**
- Los parámetros OAuth actuales (`spark.hadoop.fs.azure.account.oauth2.*`) se configuran en el cluster y NO se pueden migrar a serverless.
- La autenticación DEBE pasar por Unity Catalog + Managed Identity.

**Riesgo: Serverless compute no está disponible en todas las regiones Azure**
- El workspace está en `East US` — esta región soporta serverless, pero es un riesgo a verificar.
- La habilitación de serverless es manual (UI/Azure Portal) y no se puede hacer vía Terraform.

### Impacto en Costos

| Aspecto | Cluster Clásico | Serverless Jobs | New Cluster (efímero) |
|---------|----------------|-----------------|----------------------|
| Costo base | $0.10-0.40/hr (idle) | $0 (no idle) | $0 (no idle) |
| Costo por ejecución | ~5 min startup + 2 min proc | ~5-10s startup + 2 min proc | ~5 min startup + 2 min proc |
| Cold start | 3-5 min (DS3_v2) | < 10s | 3-5 min (DS3_v2) |
| DBU/hr | ~0.5 DBU | ~1.5-2x DBU premium | ~0.5 DBU |
| Ideal para | Carga continua | Carga batch esporádica | Carga batch esporádica |

Serverless tiene un **precio premium por DBU** (~1.5-2x) pero elimina el costo idle del cluster. Para un job que corre cada 6h (~4 ejecuciones/día), serverless suele ser **más barato** porque solo pagas cuando ejecutás.

### Recommendation

**Enfoque recomendado: ADF Job Activity + Databricks Jobs Serverless — Approach 2**

Razones:
1. **Serverless real**: Los notebooks corren en serverless compute sin aprovisionar VMs.
2. **Nativo de ADF**: La `AzureDatabricksJob` activity es soporte oficial, no un hack con Web Activity. El linked service no necesita config de cluster.
3. **ADF mantiene orquestación**: El pipeline, datasets, y schedule trigger siguen en ADF.
4. **Migración gradual**: Se puede migrar un notebook a la vez sin romper el pipeline actual.
5. **Unity Catalog ya está**: Las external locations existen, solo falta adaptar los notebooks y eliminar el Spark conf OAuth.

Secuencia de migración propuesta:
1. Habilitar serverless compute en el workspace de Databricks (manual: UI → Settings → Serverless)
2. Crear `databricks_job` resources en Terraform para `01_bronze_to_silver` y `02_silver_to_gold`
3. Adaptar notebooks para usar external locations de Unity Catalog en vez de ABFSS + Spark conf OAuth
4. Agregar Job Activities en el pipeline ADF apuntando a los `jobId` de Databricks
5. Eliminar `databricks_cluster`, Spark conf OAuth, y variables obsoletas (`azure_client_id`, `azure_client_secret` para DB)
6. Eliminar o simplificar el ADF Linked Service (ya no necesita `existing_cluster_id`)

### Configuración Serverless Necesaria (no-Terraform)

Algunos pasos SON manuales y deben documentarse:
- **Habilitar serverless compute** en el workspace (Azure Databricks Settings → Serverless Compute)
- **Regiones**: Verificar que `East US` soporta serverless compute para jobs
- **Permisos**: El Service Principal o la Managed Identity debe tener permisos para ejecutar jobs serverless
- **Cuota**: Verificar cuota de DBU serverless en la suscripción

### Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | **Serverless no disponible en la región** | High | Verificar antes de comenzar. `East US` generalmente soporta, pero debe confirmarse. Alternativa: `new_cluster_config` (approach 1) |
| 2 | **Spark conf OAuth no funciona en serverless** | High | Los notebooks deben migrar de ABFSS directo a external locations de Unity Catalog. Esto requiere cambios en el código PySpark. |
| 3 | **Breaking change en notebooks** | Medium | Los scripts PySpark usan `dbutils.widgets` y rutas ABFSS que dependen de Spark conf. Con serverless no hay Spark conf → migrar a UC external locations. |
| 4 | **Serverless tiene precio premium (1.5-2x DBU)** | Low-Medium | Para 4 ejecuciones/día el costo total es menor (no hay idle). Monitorear primer mes. |
| 5 | **Habilitación manual no gestionable por Terraform** | Low | El feature flag de serverless no es un recurso Terraform. Debe documentarse como prerequisito. |
| 6 | **dim_location usa `monotonically_increasing_id`** | Low | Pre-existente, no relacionado con serverless. Pero conviene arreglarlo si se tocan los notebooks. |

### Ready for Proposal

**Yes** — la exploración está actualizada con el descubrimiento clave de Jun 2026: ADF tiene soporte nativo para Databricks Jobs Serverless vía `AzureDatabricksJob` activity. La recomendación es el **Approach 2: ADF Job Activity + Databricks Jobs Serverless**, que requiere que el orchestrator comunique al usuario:

1. Serverless compute debe habilitarse manualmente en el workspace de Databricks (no automatizable vía Terraform).
2. Los notebooks PySpark necesitan cambios para usar Unity Catalog en vez de ABFSS directo con Spark conf OAuth.
3. La migración puede hacerse en fases: primero Unity Catalog, luego serverless jobs, luego limpieza.
4. ~~Ya no se necesita Web Activity ni API calls manuales~~ — ADF lo soporta nativamente.
5. Existe una alternativa más simple (new_cluster_config) que NO es serverless real pero elimina el cluster persistente.

**Corrección respecto a la exploración original**: La versión anterior asumía incorrectamente que ADF no podía apuntar directamente a serverless compute. La documentación oficial de Microsoft confirma que la `AzureDatabricksJob` activity ejecuta serverless automáticamente sin configuración de cluster en el linked service. Esto simplifica significativamente la arquitectura.
