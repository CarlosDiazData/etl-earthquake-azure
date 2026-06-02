# Tasks: Dev Infra Readiness

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~200 (7 files) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

## Phase 1: Foundation

- [x] 1.1 Add `azure_client_id`, `azure_client_secret`, `azure_tenant_id` variables to `terraform/variables.tf`
- [x] 1.2 Create `.gitignore` with Terraform (`.terraform/`, `*.tfstate*`, `*.tfvars`, `tfplan`), IDE, OS, Python entries

## Phase 2: Core Implementation

- [x] 2.1 Add `backend "azurerm"` block to `terraform/main.tf` (state storage account + container + key)
- [x] 2.2 Update Databricks provider in `terraform/main.tf` with `azure_*` auth fields (same SP as AzureRM)
- [x] 2.3 Create `terraform/outputs.tf` with 8 outputs: resource_group_name, storage_account_name/endpoint, databricks workspace URL/ID/location, data_factory_name/principal_id

## Phase 3: CI/CD Integration

- [x] 3.1 Add `-var-file=dev.tfvars` to `terraform plan` and `terraform apply` steps in `.github/workflows/deploy.yml`
- [x] 3.2 Add `TF_VAR_azure_client_id/secret/tenant_id` env vars from secrets and `DATABRICKS_TOKEN` placeholder to `.github/workflows/deploy.yml`
- [x] 3.3 Create `terraform/dev.tfvars` from `terraform.tfvars.example` (tracked in Git for CI)

## Phase 4: Documentation

- [x] 4.1 Update `README.md` with bootstrap commands for state storage account, prerequisites checklist, and DATABRICKS_TOKEN setup instructions

## Verification

- [ ] Run `terraform fmt -check -recursive` — no formatting issues (skipped: terraform not installed in env)
- [ ] Run `terraform validate` passes with dev.tfvars (skipped: terraform not installed in env)
- [ ] Run `terraform init -backend=false` confirms no syntax errors (skipped: terraform not installed in env)
