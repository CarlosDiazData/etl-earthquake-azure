# Tasks: ADF Objects via Code (Terraform Native)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~95–105 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Design Corrections to Apply

1. **`msi_workspace_id`** (not `msi_work_space_resource_id`). The design.md uses the deprecated name. Correct attribute: `msi_workspace_id = azurerm_databricks_workspace.main.id`.
2. **`azurerm_data_factory_dataset_json`** (not delimited_text) — confirmed, bronze stores GeoJSON.

## Phase 1: Linked Services (Foundation)

- [x] 1.1 Add `azurerm_data_factory_linked_service_web.usgs` — `LS_USGS_HTTP`, URL `https://earthquake.usgs.gov/fdsnws/event/1/`, anonymous auth
- [x] 1.2 Add `azurerm_data_factory_linked_service_azure_blob_storage.adls` — `LS_ADLS_GEN2`, MI auth, `service_endpoint = azurerm_storage_account.main.primary_blob_endpoint`
- [x] 1.3 Add `azurerm_data_factory_linked_service_azure_databricks.databricks` — `LS_DATABRICKS`, MSI auth via `msi_workspace_id`, `existing_cluster_id = databricks_cluster.job_cluster.id`, `adb_domain = azurerm_databricks_workspace.main.workspace_url`

## Phase 2: Datasets + Pipeline + Trigger (Core)

- [x] 2.1 Add `azurerm_data_factory_dataset_http.usgs` — `DS_USGS_GEOJSON`, relative URL `query?format=geojson&minmagnitude=4`
- [x] 2.2 Add `azurerm_data_factory_dataset_json.bronze` — `DS_ADLS_BRONZE_JSON`, `azure_blob_storage_location` container `bronze`, path `raw/`
- [x] 2.3 Add `azurerm_data_factory_pipeline.master` — `PL_MasterPipeline`, `activities_json = jsonencode([...])` with 3 sequential activities: CopyData → NB01 → NB02. Pass notebook params (`adls_container`, `adls_account`, `bronze_path`, `silver_path`, `gold_path`)
- [x] 2.4 Add `azurerm_data_factory_trigger_schedule.every_6h` — `TR_Schedule_6h`, frequency Hour / interval 6, linked to PL_MasterPipeline

## Phase 3: Documentation

- [x] 3.1 Remove "Configuración post-deploy (ADF Studio)" section from README.md (lines 101–110)
- [x] 3.2 Update plan.md — change Pipeline + Trigger rows from "Manual en ADF Studio" to "Terraform". Remove notes about manual ADF setup

## Phase 4: Verification

- [x] 4.1 Run `terraform validate` — confirm all 7 resources parse correctly (PASSED)
- [x] 4.2 Run `terraform plan` — confirm additions, 0 changes to existing resources (PASSED: 4 AzureRM additions shown; 3 Databricks-linked blocked by auth — pre-existing limitation)
- [x] 4.3 Review README.md and plan.md — no remaining references to manual ADF Studio setup
