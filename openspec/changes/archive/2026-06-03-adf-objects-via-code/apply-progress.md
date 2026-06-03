# Apply Progress: ADF Objects via Code (Terraform Native)

## Status: ✅ COMPLETED

## Summary

All 12 tasks across 4 phases implemented. 7 Terraform resources added to `terraform/datafactory.tf`. README.md and plan.md purged of manual ADF Studio references.

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `terraform/datafactory.tf` | Modified (+164 lines) | Appended 7 resources: 3 linked services, 2 datasets, 1 pipeline, 1 trigger |
| `README.md` | Modified (-9 lines) | Removed "Configuración post-deploy (ADF Studio)" section |
| `plan.md` | Modified | Table rows updated, notes/order/outstanding items cleaned of manual ADF references |
| `openspec/changes/adf-objects-via-code/tasks.md` | Modified | All 12 checkboxes marked as completed |

## Resources Added (7 total)

### Phase 1: Linked Services
1. **`LS_USGS_HTTP`** — `azurerm_data_factory_linked_service_web.usgs` — URL: `https://earthquake.usgs.gov/fdsnws/event/1/`, Anonymous auth
2. **`LS_ADLS_GEN2`** — `azurerm_data_factory_linked_service_azure_blob_storage.adls` — MI auth, `service_endpoint = azurerm_storage_account.main.primary_blob_endpoint`
3. **`LS_DATABRICKS`** — `azurerm_data_factory_linked_service_azure_databricks.databricks` — MSI via `msi_workspace_id`, `adb_domain` from workspace URL, `existing_cluster_id`

### Phase 2: Datasets + Pipeline + Trigger
4. **`DS_USGS_GEOJSON`** — `azurerm_data_factory_dataset_http.usgs` — relative URL `query?format=geojson&minmagnitude=4`, GET method
5. **`DS_ADLS_BRONZE_JSON`** — `azurerm_data_factory_dataset_json.bronze` — `azure_blob_storage_location` container=bronze, path=raw/
6. **`PL_MasterPipeline`** — `azurerm_data_factory_pipeline.master` — 3 sequential activities: Copy_USGS_To_Bronze → Notebook_Bronze_To_Silver → Notebook_Silver_To_Gold. Notebook params match widget names in 01_bronze_to_silver.py and 02_silver_to_gold.py. `activities_json` uses `jsonencode()` for plan-time validation.
7. **`TR_Schedule_6h`** — `azurerm_data_factory_trigger_schedule.every_6h` — Hour/6 interval, linked to PL_MasterPipeline

## Design Corrections Applied

| Correction | Detail |
|------------|--------|
| `msi_workspace_id` (not deprecated `msi_work_space_resource_id`) | Used `msi_workspace_id = azurerm_databricks_workspace.main.id` + `adb_domain = azurerm_databricks_workspace.main.workspace_url` |
| `azurerm_data_factory_dataset_json` (not delimited_text) | JSON type used — matches `spark.read.json()` in 01_bronze_to_silver.py |

## Verification Results

### terraform validate: ✅ PASSED
Configuration is valid. All attribute names, references, and `jsonencode()` structure correct.

### terraform plan: ✅ PARTIAL (expected)
- **4 AzureRM resources** shown as `+ create`: LS_USGS_HTTP, LS_ADLS_GEN2, DS_USGS_GEOJSON, DS_ADLS_BRONZE_JSON
- **3 remaining resources** (LS_DATABRICKS, pipeline, trigger) blocked by Databricks provider auth — the `azure_client_id` placeholders can't authenticate. This is a **pre-existing limitation** (valid Databricks credentials required for full plan), NOT a config error.
- **0 changes** to existing resources — confirmed

### ADF Studio references: ✅ CLEAN
No remaining manual ADF Studio setup instructions in README.md or plan.md.

## Issues Found

| Issue | Severity | Detail |
|-------|----------|--------|
| README.md line 52 says "CSV" instead of "GeoJSON" | Low | Data flow description, not related to ADF setup. Not in scope of this change. |
| Full plan requires Databricks auth | Low | Pre-existing limitation; dummy credentials can't authenticate to Databricks provider data sources |
