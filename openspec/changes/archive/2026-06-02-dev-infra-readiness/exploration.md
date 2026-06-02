## Exploration: dev-infra-readiness

### Current State

The project is a migration from AWS to Azure — an ETL pipeline that pulls earthquake data from USGS, ingests it into ADLS Bronze via ADF, transforms it in Databricks (Silver → Gold), and stores the final Star Schema in Delta format. The Terraform code, Databricks notebooks, and CI/CD scaffolding are largely in place but have critical gaps that would block a first successful `terraform apply` and subsequent operations.

**What exists:**
- `main.tf` — providers (azurerm + databricks), resource group, provider configs
- `storage.tf` — ADLS Gen2 account + bronze/silver/gold containers
- `databricks.tf` — workspace, job cluster, notebook uploads via `databricks_notebook`
- `datafactory.tf` — Data Factory + RBAC role assignments (Storage Blob Data Contributor + Contributor on Databricks)
- `variables.tf` — 7 variables, 4 without defaults
- `terraform.tfvars.example` — dev values for all required vars
- `.github/workflows/deploy.yml` — basic Terraform plan/apply on push to main
- `plan.md` and `README.md` — good documentation of the architecture

**What's missing or broken:**
1. **No `outputs.tf`** — post-deploy values (storage endpoint, workspace URL, etc.) are not exposed
2. **No `.gitignore`** — `.terraform/`, `tfplan`, `.tfvars`, and state files would be committed
3. **`deploy.yml` has critical issues** — missing `-var-file` (will fail in CI since 4 variables have no defaults), uses client-secret auth instead of OIDC, no state backend configured
4. **`DATABRICKS_TOKEN` not integrated** — the Databricks provider in `main.tf` has no auth mechanism configured, and there's no PAT token flow for ADF

### Affected Areas

- `terraform/outputs.tf` — **needs creation**: exposes storage account name, primary blob endpoint, Databricks workspace URL/ID, Data Factory name, resource group name
- `.gitignore` — **needs creation**: prevent committing Terraform working dir / state / plans / credentials
- `.github/workflows/deploy.yml` — **needs fixes**: add `-var-file`, configure state backend, fix Databricks provider auth
- `terraform/main.tf` — **needs fixes**: Databricks provider missing auth config (currently only sets `host`)
- `terraform/databricks.tf` — **potential addition**: `databricks_token` resource if we want Terraform to generate the ADF PAT token
- `terraform/versions.tf` — **potential creation**: extract `required_version` and `required_providers` from `main.tf` (convention)
- `README.md` — update post-deploy instructions with accurate output values

### Approaches

#### 1. `outputs.tf` — What to expose

| Output | Value | Consumer |
|--------|-------|----------|
| `resource_group_name` | `azurerm_resource_group.main.name` | Deployer, cross-ref |
| `storage_account_name` | `azurerm_storage_account.main.name` | ADF Linked Service |
| `storage_account_primary_blob_endpoint` | `azurerm_storage_account.main.primary_blob_endpoint` | ADF ADLS connection |
| `databricks_workspace_url` | `azurerm_databricks_workspace.main.workspace_url` | ADF Linked Service, Databricks provider |
| `databricks_workspace_id` | `azurerm_databricks_workspace.main.workspace_id` | ADF Linked Service |
| `databricks_workspace_location` | `azurerm_databricks_workspace.main.location` | Reference |
| `data_factory_name` | `azurerm_data_factory.main.name` | ADF Studio navigation |
| `data_factory_identity_principal_id` | `azurerm_data_factory.main.identity[0].principal_id` | Auditing |

**Effort:** Low — 10-15 lines of HCL.

#### 2. `.gitignore` — Entries needed

```
# Terraform
.terraform/
*.tfstate
*.tfstate.backup
*.tfstate.lock.info
crash.log
crash.*.log

# Plans
tfplan
*.tfplan

# Variable files (but keep .example)
*.tfvars
!terraform.tfvars.example

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Python (databricks notebooks)
__pycache__/
*.pyc
.venv/
```

**Effort:** Low — single file creation.

#### 3. `deploy.yml` — Three sub-issues

**3a. Missing `-var-file` (BLOCKER)**

The workflow runs `terraform plan -out=tfplan` and `terraform apply tfplan` without any `-var-file` flag. Variables `resource_group_name`, `storage_account_name`, `data_factory_name`, and `databricks_workspace_name` have **no defaults**. In CI, Terraform will error with "required variable not set" since there's no TTY for interactive input.

**Approach A — Commit `dev.tfvars` to repo** (recommended for dev):
- Create `terraform/dev.tfvars` with the dev values
- Add `-var-file=dev.tfvars` to plan and apply commands
- `.gitignore` keeps `.tfvars` but we explicitly allow `dev.tfvars` or use a specific name

**Approach B — Pass vars via GitHub Secrets + `-var` flags**:
- Each required var becomes a GitHub Secret
- `terraform plan -var="resource_group_name=${{ secrets.TF_VAR_resource_group_name }}" -out=tfplan`
- More secure but more verbose and harder to maintain

**Approach C — GitHub Environments with variable sets**:
- Use GitHub Environments to store `TF_VAR_*` variables
- Referenced automatically by Terraform

**Recommendation:** Approach A for dev (pragmatic, the values aren't secrets — they're just resource names). For production, migrate to Approach B or C.

**3b. Auth mechanism: Service Principal vs OIDC**

The current workflow sets `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` as env vars. This is **Service Principal + client secret** authentication — NOT OIDC.

**Current (client secret):**
- Pros: Simple, fewer moving parts, well-documented
- Cons: Long-lived secret that must be rotated, stored in GitHub Secrets

**Alternative (OIDC):**
- Pros: No long-lived secrets, short-lived tokens, Azure AD federated identity
- Cons: More complex setup (Azure AD App Registration + federated credential + `azure/login@v1` step)
- Requires: `ARM_USE_OIDC=true` + `azure/login@v1` action + federated credential in Azure AD

**Recommendation:** Stick with Service Principal for now (it works), but document OIDC as a future improvement. The current setup lacks the `azure/login@v1` step which is needed if we wanted OIDC — the `ARM_*` env vars alone are correct for client-secret auth.

**3c. Missing state backend**

The workflow runs `terraform init` and `terraform plan/apply` but there's **no `backend` configuration** in `main.tf`. By default, Terraform stores state **locally**, which means:
- Each CI run starts with empty state
- The runner's workspace is ephemeral — state is lost after the job
- Terraform will try to **recreate everything** on every run

This is a **BLOCKER** — without a remote backend, the workflow is non-functional for repeated deployments.

**Fix:** Add an `azurerm` backend block in `main.tf`:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "satearthquakeetltfstate"
    container_name       = "tfstate"
    key                  = "etl-earthquake-azure.tfstate"
  }
  # ... existing required_providers ...
}
```

The storage account for state must exist *before* the first apply (bootstrapping).

**Effort for entire deploy.yml:** Medium — 3 changes (backend config, var-file, optional auth update).

#### 4. `DATABRICKS_TOKEN` for ADF

**Current state:**
- No reference to `DATABRICKS_TOKEN` in Terraform or CI/CD
- `plan.md` explicitly says: "Databricks PAT token se genera manualmente y se guarda en GitHub Secrets"
- `README.md` mentions PAT token for ADF Linked Service

**Databricks provider auth gap:**
The provider in `main.tf` only sets `host`:
```hcl
provider "databricks" {
  host = azurerm_databricks_workspace.main.workspace_url
}
```

No `token`, no `azure_*` auth fields. Terraform will try default Azure auth (Azure CLI or Managed Identity), which won't exist in GitHub Actions. This means:
- `terraform plan` **will fail** when it tries to refresh `databricks_notebook`, `databricks_cluster`, etc.
- The Databricks provider CANNOT create resources without authentication

**Fix the provider auth:**
Use the same Service Principal that authenticates AzureRM:
```hcl
provider "databricks" {
  host = azurerm_databricks_workspace.main.workspace_url
  azure_client_id       = var.azure_client_id     # same SP as AzureRM
  azure_client_secret   = var.azure_client_secret
  azure_tenant_id       = var.azure_tenant_id
  azure_workspace_resource_id = azurerm_databricks_workspace.main.id
}
```

This avoids needing a PAT token for Terraform operations entirely.

**What about the ADF PAT token?**
ADF needs a Databricks PAT token for its Linked Service. Options:

| Option | Description | Pros | Cons |
|--------|------------|------|------|
| **A. Manual + GitHub Secret** | Generate token in Databricks UI, save as `DATABRICKS_TOKEN` in GitHub Secrets | Simple, matches plan.md | Manual step, token expires |
| **B. Terraform-generated** | Add `databricks_token` resource, output the value, store in Key Vault or GH Secret | Automated, auditable | Token value sensitive — outputting is risky; needs Key Vault |
| **C. AAD token in ADF** | Use ADF's Managed Identity to auth to Databricks via Azure AD | No PAT token needed | Requires Databricks Premium (we have it) + AAD token passthrough config |

**Recommendation:** Approach A for now (matches existing plan), with Approach C as the long-term goal. If we do implement `databricks_token` in Terraform (Approach B), the token should go to Azure Key Vault, not Terraform outputs.

### Recommendation

**Implement in this order (priority):**

1. **Add `terraform/backend` block** — BLOCKER. Without remote state, CI is non-functional. Bootstrap the state storage account manually, then add the backend config.
2. **Fix `deploy.yml`** — Add `-var-file=dev.tfvars` to plan and apply commands. This unblocks the workflow.
3. **Add `.gitignore`** — Prevent accidental commits of state and credentials.
4. **Fix Databricks provider auth** — Add `azure_*` fields to the provider config in `main.tf` so the provider works in CI without a PAT token.
5. **Add `outputs.tf`** — Essential outputs for post-deploy configuration (storage endpoint, workspace URL, workspace ID).
6. **Add `DATABRICKS_TOKEN` GitHub Secret** — Document in the deploy workflow and README that this secret needs to be created manually for ADF Linked Service.
7. **Create `dev.tfvars`** — From the existing `terraform.tfvars.example`, but tracked in Git for CI.

### Risks

- **Remote state bootstrapping is manual** — Someone needs to `az storage account create` and configure the backend before the first CI run. This is a one-time task but can't be automated within the same config (chicken-and-egg).
- **Both AzureRM and Databricks providers must share credentials** — The Service Principal needs `Contributor` at the subscription level (or at least on the resource group and Databricks workspace). If the SP lacks permissions on Databricks, Terraform will fail partway through apply.
- **PAT token lifecycle** — If using a manual PAT token, it will expire (default 90 days). Someone must rotate it in GitHub Secrets. If using Terraform to generate it, the token value in outputs is a security concern.
- **`dev.tfvars` in Git** — Resource names aren't secrets, but having environment-specific files in Git encourages drift between environments. Consider GitHub Environments or CI variables for prod later.

### Ready for Proposal

Yes — these gaps are well-understood and the fixes are straightforward. The proposal should focus on the BLOCKER issues first (state backend + `-var-file`) since `terraform apply` will fail in CI without them.
