# Design: Migrate Databricks from Classic Clusters to Serverless

## Technical Approach

Replace `databricks_cluster.job_cluster` and ADF `DatabricksNotebook` activities with `databricks_job` resources (serverless by default) and ADF `AzureDatabricksJob` activities. Notebook auth migrates from Spark conf OAuth → Unity Catalog Managed Identity via existing storage credential. ADF remains the orchestrator; Databricks handles compute automatically.

## Architecture Decisions

| Option | Tradeoff | Decision |
|--------|----------|----------|
| `databricks_job` (serverless) vs classic cluster | No idle DBU cost, no cluster management, but cold start ~15-30s | **Serverless** — cost savings outweigh cold start |
| `AzureDatabricksJob` vs `DatabricksNotebook` activity | Job activity is serverless-native, jobId-based, but requires pre-deployed job | **AzureDatabricksJob** — no cluster config needed |
| UC MI vs Spark conf OAuth | MI is serverless-compatible, centralized, no secret rotation | **UC MI** — already provisioned, zero-code auth change |
| Keep widget params vs remove | Removing cleans notebook code but requires Terraform parameter sync | **Simplify** — remove `adls_account`/`adls_container`, keep `*_path` params only |

## Data Flow

```
ADF Trigger (6h)
  │
  ▼
Copy Activity (USGS HTTP → ADLS Bronze)
  │
  ▼
AzureDatabricksJob: bronze_to_silver
  │  Serverless compute, UC MI auth
  │  Reads:  abfss://bronze@.../raw/   (UC: el-earthquake-bronze)
  │  Writes: abfss://silver@.../cleansed/ (UC: el-earthquake-silver)
  ▼
AzureDatabricksJob: silver_to_gold
  │  Reads:  abfss://silver@.../cleansed/
  │  Writes: abfss://gold@.../dimensional/ (UC: el-earthquake-gold)
  ▼
ADLS Gold (Parquet Star Schema)
```

## Authentication Flow

```
AzureDatabricksJob (ADF MSI → Databricks Workspace)
  │
  ▼
Serverless Compute (Databricks-managed)
  │  No Spark conf — UC resolves auth
  ▼
Unity Catalog Storage Credential (Managed Identity)
  │  access_connector_id → UC access connector
  ▼
ADLS Gen2 (RBAC: Storage Blob Data Contributor on connector)
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `terraform/databricks.tf` | Modify | Remove `databricks_cluster`, add `databricks_job` ×2 |
| `terraform/datafactory.tf` | Modify | Drop `existing_cluster_id`; `Notebook` → `AzureDatabricksJob` activities |
| `terraform/variables.tf` | Modify | Remove `azure_client_id`, `azure_client_secret` (no longer used in Spark conf) |
| `databricks/01_bronze_to_silver.py` | Modify | Remove `adls_container`, `adls_account` widgets; use UC external location paths |
| `databricks/02_silver_to_gold.py` | Modify | Remove `adls_account` widget; use UC external location paths |

## Terraform Snippets

### databricks_job resources (replaces `databricks_cluster`)

```hcl
resource "databricks_job" "bronze_to_silver" {
  name = "01_Bronze_To_Silver"

  notebook_task {
    notebook_path = databricks_notebook.bronze_to_silver.path
    base_parameters = {
      silver_path = "cleansed/"
    }
  }

  max_concurrent_runs = 1
  # Serverless: no job_cluster_key, existing_cluster_id, or new_cluster
  performance_target = "PERFORMANCE_OPTIMIZED"

  depends_on = [databricks_notebook.bronze_to_silver]
}

resource "databricks_job" "silver_to_gold" {
  name = "02_Silver_To_Gold"

  notebook_task {
    notebook_path = databricks_notebook.silver_to_gold.path
    base_parameters = {
      gold_path = "dimensional/"
    }
  }

  max_concurrent_runs = 1
  performance_target = "PERFORMANCE_OPTIMIZED"

  depends_on = [databricks_notebook.silver_to_gold]
}
```

### ADF Linked Service (drops `existing_cluster_id`)

```hcl
resource "azurerm_data_factory_linked_service_azure_databricks" "databricks" {
  name             = "LS_DATABRICKS"
  data_factory_id  = azurerm_data_factory.main.id
  msi_workspace_id = azurerm_databricks_workspace.main.id
  adb_domain       = azurerm_databricks_workspace.main.workspace_url
  # existing_cluster_id REMOVED — serverless doesn't need it
}
```

### ADF Pipeline Activities (key change: Notebook → AzureDatabricksJob)

```json
{
  "name": "Job_Bronze_To_Silver",
  "type": "AzureDatabricksJob",
  "dependsOn": [{ "activity": "Copy_USGS_To_Bronze", "dependencyConditions": ["Succeeded"] }],
  "linkedServiceName": { "referenceName": "LS_DATABRICKS", "type": "LinkedServiceReference" },
  "typeProperties": {
    "jobId": "${databricks_job.bronze_to_silver.id}"
  }
},
{
  "name": "Job_Silver_To_Gold",
  "type": "AzureDatabricksJob",
  "dependsOn": [{ "activity": "Job_Bronze_To_Silver", "dependencyConditions": ["Succeeded"] }],
  "linkedServiceName": { "referenceName": "LS_DATABRICKS", "type": "LinkedServiceReference" },
  "typeProperties": {
    "jobId": "${databricks_job.silver_to_gold.id}"
  }
}
```

> Activities JSON must use `jsonencode()` (not raw string) to interpolate `databricks_job.*.id` values.

## Notebook Auth Migration

Both notebooks currently build ABFSS paths from widget parameters and rely on Spark conf OAuth. Migration:

1. **Remove widgets**: `adls_container`, `adls_account` removed. Storage account name is now a constant in the notebook (or read from UC metadata).
2. **Paths become constant**: `BRONZE_PATH = "abfss://bronze@${STORAGE_ACCOUNT}.dfs.core.windows.net/raw/"` (hardcoded storage account).
3. **Auth**: Serverless compute auto-resolves UC storage credential MI — no Spark conf needed. Existing `databricks_storage_credential.main` covers all containers.
4. **Remaining params**: `silver_path`, `gold_path` kept as job parameters for flexibility (subdirectory changes).

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Terraform | `terraform validate && terraform plan` | CI pipeline; verify no cluster resources, jobs created |
| Notebook | Unit logic unchanged (only path construction) | Manual run in Databricks UI after deploy |
| Integration | End-to-end pipeline | Trigger ADF pipeline; verify bronze→silver→gold completes in < 3 min |
| Rollback | Revert to previous commit | `terraform apply` from previous state; no data loss |

## Migration / Rollout

1. Deploy `databricks_job` resources first (`terraform apply -target`)
2. Deploy ADF changes (linked service + pipeline)
3. Run one notebook manually to verify UC auth
4. Trigger full pipeline and validate output
5. `terraform state rm databricks_cluster.job_cluster` (cleanup)

Rollback: Revert to previous commit, `terraform apply`. No data migration needed — ADLS storage is unchanged.

## Open Questions

- [ ] Can `azure_client_id` / `azure_client_secret` be fully removed from `variables.tf` given the `databricks` provider still needs auth? Provider auth may switch to Azure CLI/OIDC — verify before removing.
- [ ] Serverless availability in East US: verify before deploy. Fallback: add `new_cluster` block with `data_security_mode = "SINGLE_USER"` as safety net.
- [ ] Gold `saveAsTable()` in `02_silver_to_gold.py`: UC catalog registration needed or keep `option("path", ...)` pattern?
