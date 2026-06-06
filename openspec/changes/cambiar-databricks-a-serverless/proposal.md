# Proposal: Migrate Databricks from Classic Clusters to Serverless

## Intent

Eliminate `databricks_cluster.job_cluster` and migrate to serverless compute via ADF's native `AzureDatabricksJob` activity + Terraform `databricks_job` resources. Reduces cost (no idle DBU), simplifies auth (Unity Catalog MI instead of Spark conf OAuth), eliminates cluster management.

## Scope

### In Scope
- `databricks_job` resources ×2 with serverless compute (default when no cluster specified)
- ADF pipeline: Notebook activities → `AzureDatabricksJob` activities
- Notebooks: ABFSS + Spark conf → Unity Catalog external location paths
- Remove `databricks_cluster`, `existing_cluster_id`, Spark conf OAuth, `azure_client_id`, `azure_client_secret`

### Out of Scope
- Databricks Workflows (keeps ADF as orchestrator)
- SQL Warehouses, `dim_location` fix, CI/CD changes

## Capabilities

### New Capabilities
- `databricks-jobs`: Terraform `databricks_job` resources with `notebook_task`, serverless compute, `performance_target`, and `environment` blocks for pip deps
- `databricks-uc-auth`: Unity Catalog external location auth via Managed Identity, replacing Spark conf OAuth

### Modified Capabilities
- `adf-linked-services`: Databricks linked service drops `existing_cluster_id`; workspace URL + MSI auth only
- `adf-pipeline-orchestration`: Notebook activities become `AzureDatabricksJob` activities with `jobId` refs; sequential `depends_on` flow preserved

## Approach

ADF's `AzureDatabricksJob` runs serverless automatically — no Web Activity, no cluster config. Terraform: `databricks_job` → serverless (default). Pipeline: `jobId` references instead of notebook paths.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `terraform/databricks.tf` | Replaced | Remove cluster, add `databricks_job` ×2 |
| `terraform/datafactory.tf` | Modified | Replace `existing_cluster_id` + Notebook → Job activities |
| `terraform/variables.tf` | Modified | Remove `azure_client_id`, `azure_client_secret` |
| `databricks/01_bronze_to_silver.py` | Modified | ABFSS → UC external location paths |
| `databricks/02_silver_to_gold.py` | Modified | ABFSS → UC external location paths |
| `openspec/specs/adf-linked-services/` | Updated | Drop cluster requirement |
| `openspec/specs/adf-pipeline-orchestration/` | Updated | Notebook → Job activities |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Serverless unavailable in East US | Low | Verify; fallback to `new_cluster_config` |
| UC external location auth fails | Medium | Credentials exist; test one notebook first |
| Breaking notebook changes | Medium | Migrate one at a time; keep old activity as fallback |

## Rollback Plan

Revert Terraform to previous commit (classic cluster + Notebook activities). Re-deploy. No data loss — ADLS storage untouched.

## Dependencies

- Serverless enabled manually in workspace UI
- UC storage credentials/external locations exist (already provisioned)
- MSI requires serverless job execution permission

## Success Criteria

- [ ] `databricks_cluster.job_cluster` removed from Terraform state
- [ ] Two `databricks_job` resources deploy with serverless compute
- [ ] ADF pipeline runs both jobs via `AzureDatabricksJob` activities
- [ ] Notebooks use UC external locations (no Spark conf OAuth)
- [ ] No idle cluster costs; pipeline < 3 min end-to-end
