# Design: ADF Objects via Code (Terraform Native)

## Technical Approach

Add 7 `azurerm_data_factory_*` resources to `terraform/datafactory.tf`, encoding linked services, datasets, pipeline, and trigger entirely in Terraform. No new variables: all references derive from existing resources (`azurerm_databricks_workspace.main.id`, `databricks_cluster.job_cluster.id`, `var.storage_account_name`, `azurerm_storage_account.main.primary_blob_endpoint`). Managed Identity auth throughout (RBAC already granted). `activities_json` uses `jsonencode()` to eliminate manual JSON syntax errors at plan time.

## Architecture Decisions

| Decision | Option | Tradeoff | Chosen | Rationale |
|----------|--------|----------|--------|-----------|
| activities_json construction | `jsonencode()` | Tight coupling to Terraform HCL | **Yes** | Validates structure at PLAN time. Raw JSON string fails at apply time. |
| | Raw heredoc string | Simpler to read | No | Syntax errors invisible until pipeline runtime. |
| ADLS linked service type | `azure_blob_storage` (MI) | Uses blob endpoint, not dfs | **Yes** | Compatible with ADLS Gen2. Pairs natively with `azure_blob_storage_location` on JSON dataset. RBAC already covers blob endpoint. |
| | `azure_data_lake_storage_gen2` | Requires separate dataset type | No | Unnecessary for this sink pattern. |
| USGS query URL | Static wide window (2024-2026) | Not sliding, but pipeline runs every 6h append data | **Yes** | Notebook reads ALL files in `bronze/raw/` — idempotent. Parameterized dataset adds complexity with no benefit. |
| | Pipeline expression sliding window | Dynamic time range | No | |
| Pipeline execution | Sequential (dependsOn with Succeeded) | Latency = sum of activity durations | **Yes** | Notebook 02 depends on Silver data written by Notebook 01. Notebook 01 depends on Bronze data written by Copy. Must be sequential. |
| | Parallel fan-out | Lower latency | No | Would fail — downstream notebooks need upstream outputs. |

## Data Flow

```
[USGS API] ──HTTP GET──▶ [Copy Data Activity] ──JSON──▶ [ADLS: bronze/raw/]
                                                              │
                                                              ▼
                                              [NB 01: bronze_to_silver]
                                              flattens GeoJSON → Delta ──▶ [ADLS: silver/cleansed/]
                                                                                │
                                                                                ▼
                                                                [NB 02: silver_to_gold]
                                                                star schema → Parquet ──▶ [ADLS: gold/dimensional/]
```

**Sequence:**

    TR_Schedule_6h ──fires──▶ PL_MasterPipeline
      ├──(1) Copy_USGS_To_Bronze → GET usgs → sink ADLS bronze/raw/usgs_earthquakes.json
      ├──(2) Notebook_Bronze_To_Silver → read bronze → write Delta to silver
      └──(3) Notebook_Silver_To_Gold → read silver → write Parquet to gold

Each activity gates on predecessor `Succeeded`.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `terraform/datafactory.tf` | Modify | Append 7 resources (~80 lines): 3 linked services, 2 datasets, 1 pipeline, 1 trigger |
| `README.md` | Modify | Remove "Configuración post-deploy (ADF Studio)" section |
| `plan.md` | Modify | Mark pipeline + trigger as Terraform-provisioned |

## Resource Dependency Chain

```
azurerm_data_factory.main
 ├── azurerm_data_factory_linked_service_web.usgs
 │    url = "https://earthquake.usgs.gov/fdsnws/event/1/"
 │    authentication_type = "Anonymous"
 ├── azurerm_data_factory_linked_service_azure_blob_storage.adls
 │    use_managed_identity = true
 │    service_endpoint = azurerm_storage_account.main.primary_blob_endpoint
 ├── azurerm_data_factory_linked_service_azure_databricks.databricks
 │    msi_work_space_resource_id = azurerm_databricks_workspace.main.id
 │    existing_cluster_id = databricks_cluster.job_cluster.id
 ├── azurerm_data_factory_dataset_http.usgs
 │    linked_service_name = LsHttpUsgs
 │    relative_url = "query?format=geojson&starttime=2024-01-01&endtime=2026-12-31"
 ├── azurerm_data_factory_dataset_json.bronze
 │    linked_service_name = LsAdlsGen2
 │    azure_blob_storage_location { container="bronze", path="raw", filename="usgs_earthquakes.json" }
 ├── azurerm_data_factory_pipeline.master
 │    activities_json = jsonencode([CopyData, NB01, NB02])
 │    depends_on = [datasets + databricks ls]
 └── azurerm_data_factory_trigger_schedule.every_6h
      pipeline_name = PL_MasterPipeline
      frequency = "Hour", interval = 6
```

## Notebook Parameter Contract

| Notebook | Parameters (passed via ADF baseParameters) |
|----------|-------------------------------------------|
| `/Shared/earthquake-etl/01_bronze_to_silver` | `adls_container="bronze"`, `adls_account={var.storage_account_name}`, `bronze_path="raw/"`, `silver_path="cleansed/"` |
| `/Shared/earthquake-etl/02_silver_to_gold` | `adls_account={var.storage_account_name}`, `silver_path="cleansed/"`, `gold_path="dimensional/"` |

Values match notebook `dbutils.widgets.text()` defaults. `adls_account` uses `var.storage_account_name` injected via `jsonencode()` interpolation.

## Testing Strategy

| Layer | What | How |
|-------|------|-----|
| Static | `terraform validate` | Catches `jsonencode()` structural errors at plan time |
| Integration | Drift check | `terraform plan` post-apply must show zero changes |
| Runtime | Pipeline E2E | Manual trigger → verify bronze/silver/gold files in ADLS |
| Runtime | Schedule trigger | Wait for next 6h window → verify pipeline run in ADF Monitor |

## Migration / Rollout

No migration — net-new resources in existing data factory. No existing ADF objects overwritten.

**Rollback**: comment out new resources → `terraform apply` → ADF soft-deletes preserve objects → recreate manually per original README if needed.

## Open Questions

- [ ] Verify `msi_work_space_resource_id` attribute name in azurerm provider ~>4.0 (check docs at apply time)
- [ ] Confirm `azure_blob_storage_location.filename` behavior on repeated pipeline runs — adjust to timestamp-based filename if first run shows overwrite
