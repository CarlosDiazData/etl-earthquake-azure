# Tasks: Migrate Databricks from Classic Clusters to Serverless

## Review Workload Forecast

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

| Field | Value |
|-------|-------|
| Estimated changed lines | ~220 (additions + deletions) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-along |

## Phase 1: Databricks Jobs (Foundation)

- [x] 1.1 Add `databricks_job` "bronze_to_silver" in `terraform/databricks.tf` with `notebook_task` referencing `01_bronze_to_silver.py`, serverless (no cluster blocks), `performance_target`, `max_concurrent_runs = 1`
- [x] 1.2 Add `databricks_job` "silver_to_gold" in `terraform/databricks.tf` with `notebook_task` referencing `02_silver_to_gold.py`, same serverless pattern
- [x] 1.3 Remove `data.databricks_node_type.smallest`, `data.databricks_spark_version.latest_lts`, and `databricks_cluster.job_cluster` from `terraform/databricks.tf`

## Phase 2: ADF Linked Service

- [x] 2.1 Remove `existing_cluster_id = databricks_cluster.job_cluster.id` from `azurerm_data_factory_linked_service_azure_databricks.databricks` in `terraform/datafactory.tf`

## Phase 3: ADF Pipeline Migration

- [x] 3.1 Replace "Notebook_Bronze_To_Silver" activity (type `DatabricksNotebook`) with "Job_Bronze_To_Silver" (type `AzureDatabricksJob`, `jobId` referencing `databricks_job.bronze_to_silver.id`) in `terraform/datafactory.tf`
- [x] 3.2 Replace "Notebook_Silver_To_Gold" activity (type `DatabricksNotebook`) with "Job_Silver_To_Gold" (type `AzureDatabricksJob`, `jobId` referencing `databricks_job.silver_to_gold.id`) in `terraform/datafactory.tf`
- [x] 3.3 Remove `adls_container`, `adls_account` from baseParameters of both activities; keep `silver_path`, `gold_path`, `bronze_path`

## Phase 4: Notebook Auth Migration

- [x] 4.1 In `databricks/01_bronze_to_silver.py`: remove `adls_container` and `adls_account` widgets; hardcode storage account; use constant ABFSS paths; keep `bronze_path` and `silver_path` as job parameters only
- [x] 4.2 In `databricks/02_silver_to_gold.py`: remove `adls_account` widget; hardcode storage account name; use constant ABFSS paths; keep `silver_path` and `gold_path` as job parameters only

## Phase 5: Cleanup

- [~] 5.1 Remove `azure_client_id` and `azure_client_secret` variables from `terraform/variables.tf` — **SKIPPED**: `databricks` provider in `main.tf` still authenticates via these variables (see design open question). Revisit when provider auth switches to Azure CLI/OIDC.
- [x] 5.2 `terraform validate` — configuration is valid. No cluster resources, jobs created, no validation warnings.
- [ ] 5.3 Trigger ADF pipeline end-to-end; verify bronze→silver→gold completes in < 3 min — **BLOCKED**: deployment only; no terraform apply in this session.
