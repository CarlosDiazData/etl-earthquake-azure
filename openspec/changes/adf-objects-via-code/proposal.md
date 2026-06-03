# Proposal: ADF Objects via Code (Terraform Native)

## Intent

ADF objects (linked services, datasets, pipeline, trigger) are created manually in ADF Studio — invisible to Terraform state. This breaks IaC: one `terraform apply` should provision the entire pipeline.

## Scope

### In Scope
- 3 linked services: USGS HTTP, ADLS Gen2 (Managed Identity), Databricks (MSI, no PAT)
- 2 datasets: HTTP JSON source (USGS GeoJSON), JSON ADLS bronze sink
- 1 pipeline: PL_MasterPipeline (Copy Data → Notebook 01 → Notebook 02)
- 1 schedule trigger: every 6 hours
- Update README.md and plan.md to remove manual ADF Studio steps

### Out of Scope
- Git integration with ADF
- Pipeline monitoring, alerts, failure notifications
- Snowflake linked service

## Capabilities

### New Capabilities
- `adf-linked-services`: HTTP (USGS API), Azure Blob Storage (ADLS Gen2 via Managed Identity), and Azure Databricks (MSI, no PAT token) linked services as Terraform resources
- `adf-pipeline-orchestration`: PL_MasterPipeline (Copy Data + 2 Databricks Notebook activities) and 6-hour schedule trigger as Terraform resources

### Modified Capabilities
None

## Approach

Terraform-native `azurerm_data_factory_*` resources in `terraform/datafactory.tf`. No new variables: `azurerm_databricks_workspace.main.id` and `databricks_cluster.job_cluster.id` already available. Managed Identity RBAC (Storage Blob Data Contributor on ADLS, Contributor on Databricks) already assigned — no new role grants needed. Pipeline `activities_json` encodes sequential Copy Data → Notebook 01 → Notebook 02.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `terraform/datafactory.tf` | Modified | Add 7 `azurerm_data_factory_*` resources (~80 lines) |
| `README.md` | Modified | Remove "Configuración post-deploy (ADF Studio)" section |
| `plan.md` | Modified | Update component table: pipeline + trigger now Terraform |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `activities_json` syntax errors at apply time | Medium | Validate JSON against ADF pipeline schema before commit |
| Terraform destroy removes ADF objects unintentionally | Low | ADF soft-delete + resource group delete lock |
| Databricks MSI auth rejected at pipeline runtime | Low | RBAC Contributor already on workspace; verify in dev |

## Rollback Plan

1. Comment out new resources in `terraform/datafactory.tf`
2. `terraform apply` — removes resources from state (ADF soft-delete preserves objects)
3. Recreate objects manually in ADF Studio per original README instructions
4. `git revert` README.md and plan.md changes

## Dependencies

- `azurerm_data_factory.main` (deployed)
- `azurerm_role_assignment.adf_to_storage` and `adf_to_databricks` (deployed)
- `databricks_cluster.job_cluster` (deployed)

## Success Criteria

- [ ] 3 linked services appear in ADF Studio with status "Available"
- [ ] PL_MasterPipeline executes end-to-end: Copy Data copies CSV to bronze/, both notebooks complete
- [ ] Schedule trigger fires automatically every 6 hours
- [ ] `terraform plan` shows no drift after initial apply
- [ ] README.md no longer references manual ADF Studio setup
