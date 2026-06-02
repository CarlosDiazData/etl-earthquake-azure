# Proposal: dev-infra-readiness

## Intent

Fix 3 blockers and 4 gaps that prevent the ETL pipeline from deploying via CI/CD. Without these, `terraform apply` fails in GitHub Actions — no remote state, Databricks provider has no auth, and `deploy.yml` is missing `-var-file` for 4 required variables.

## Scope

**In Scope:**
- Remote state backend (`azurerm` backend block in `main.tf`)
- Databricks provider auth (`azure_*` fields in provider config)
- CI/CD `-var-file` fix (plan + apply commands in `deploy.yml`)
- `.gitignore` creation (Terraform + IDE + OS entries)
- `outputs.tf` creation (8 outputs: storage endpoint, workspace URL/ID, ADF name, principal ID, etc.)
- `terraform/dev.tfvars` committed for CI (from `.example`)
- `DATABRICKS_TOKEN` GitHub Secret documented in workflow comments

**Out of Scope:**
- OIDC migration (staying with Service Principal + client secret)
- ADF Linked Service configuration (PAT token creation is manual per plan.md)
- Production environment setup
- `versions.tf` extraction (cosmetic, deferred)

## Approach

### 1. Remote State Backend

Add `backend "azurerm"` to the existing `terraform {}` block in `main.tf`. Storage account and container must be bootstrapped manually before first CI run (`az storage account create` + `az storage container create`). This is chicken-and-egg — can't manage state storage with Terraform before Terraform has state.

### 2. Databricks Provider Auth

Replace the bare `host`-only provider with `azure_client_id`, `azure_client_secret`, `azure_tenant_id`, and `azure_workspace_resource_id`. Reuses the same Service Principal as AzureRM. Add 3 new variables to `variables.tf`; pass them as `TF_VAR_*` env vars in the workflow (mapped from existing `ARM_*` GitHub Secrets).

### 3. CI/CD Fixes

Add `-var-file=dev.tfvars` to `terraform plan` and `terraform apply` in `deploy.yml`. Add `TF_VAR_azure_*` env vars for Databricks auth. Add `DATABRICKS_TOKEN` env var placeholder with documentation comment.

### 4. `.gitignore`

Terraform patterns (`.terraform/`, `*.tfstate*`), plan files, Python artifacts, IDE/OS files. Allowlist `terraform.tfvars.example` while ignoring all other `.tfvars`.

### 5. `outputs.tf`

8 outputs: `resource_group_name`, `storage_account_name`, `storage_account_primary_blob_endpoint`, `databricks_workspace_url`, `databricks_workspace_id`, `databricks_workspace_location`, `data_factory_name`, `data_factory_identity_principal_id`.

### 6. `dev.tfvars`

Copy from `terraform.tfvars.example`. Committed to Git for CI — resource names are not secrets.

### 7. DATABRICKS_TOKEN

Workflow comment documents: "Create `DATABRICKS_TOKEN` GitHub Secret manually from Databricks UI → User Settings → Access Tokens. Used by ADF Linked Service." Long-term: Azure Key Vault.

## Delivery Strategy

Single PR (~200 lines across 7 files). Low risk — no existing resources to break. `terraform validate` is the verify gate.

## Rollback Plan

- **State backend**: Revert `backend "azurerm"` to local state, run `terraform init -reconfigure`
- **Provider auth**: Revert provider block to `host`-only; Databricks resources remain unchanged
- **dev.tfvars**: CI will fail on missing `-var-file` if file is deleted — revert the commit
- **Other files**: Standalone, safe to delete individually

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| State storage account bootstrapped with wrong name/location | Low | Document exact commands and name convention in README |
| Service Principal lacks Databricks Contributor permission | Medium | Verify RBAC before first apply; add to README prerequisites |
| `DATABRICKS_TOKEN` expires (90-day default) | Low | Document rotation in README; note Key Vault as future improvement |

## Acceptance Criteria

- [ ] `terraform init` resolves backend from CI without errors
- [ ] `terraform plan -var-file=dev.tfvars` succeeds in CI
- [ ] Databricks provider authenticates and plans notebook/cluster resources
- [ ] `.gitignore` prevents `.terraform/`, `*.tfstate`, and `*.tfvars` from being committed
- [ ] `terraform output` shows all 8 expected values after apply
- [ ] `DATABRICKS_TOKEN` secret is documented (manual creation acknowledged)

## Dependencies

- **Manual bootstrap**: State storage account + container (one-time, documented in README)
- **GitHub Secrets** (already configured): `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
- **New GitHub Secret** (manual): `DATABRICKS_TOKEN`
- Service Principal with `Contributor` on resource group and Databricks workspace
