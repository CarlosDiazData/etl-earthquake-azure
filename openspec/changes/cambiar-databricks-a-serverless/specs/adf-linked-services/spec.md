# Delta for ADF Linked Services

## MODIFIED Requirements

### Requirement: Databricks Linked Service (MSI Auth, Serverless)

The system MUST provision an `azurerm_data_factory_linked_service_azure_databricks` resource using MSI authentication against the existing Databricks workspace. The linked service MUST NOT reference `existing_cluster_id` or `new_cluster_config` — compute is defined at the job level via `AzureDatabricksJob` activities. No PAT token SHALL be used.
(Previously: referenced existing job cluster by ID)

#### Scenario: Linked service with MSI and no cluster reference

- GIVEN `azurerm_databricks_workspace.main` is deployed
- AND `azurerm_role_assignment.adf_to_databricks` grants Contributor on the workspace
- WHEN Terraform applies the Databricks linked service resource
- THEN a linked service named "LS_DATABRICKS" appears in ADF Studio with status "Available"
- AND it authenticates via Managed Identity targeting the workspace ID
- AND the linked service omits `existing_cluster_id` and `new_cluster_config` from its JSON definition

#### Scenario: Existing cluster removed without pipeline breakage

- GIVEN `databricks_cluster.job_cluster` is removed from Terraform state
- WHEN the ADF pipeline runs an `AzureDatabricksJob` activity through this linked service
- THEN the job submission succeeds because compute is resolved at the job level (serverless)
- AND ADF does not require a cluster reference in the linked service definition
