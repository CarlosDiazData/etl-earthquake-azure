# ADF Linked Services Specification

## Purpose

Define the Terraform-managed Azure Data Factory linked services that connect ADF to the USGS Earthquake API, Azure Data Lake Storage Gen2, and Azure Databricks — replacing manual ADF Studio creation with IaC.

## Requirements

### Requirement: USGS HTTP Linked Service

The system MUST provision an `azurerm_data_factory_linked_service_web` resource pointing to the USGS Earthquake API base URL (`https://earthquake.usgs.gov`).

#### Scenario: Linked service created with HTTP connector

- GIVEN `azurerm_data_factory.main` is deployed with SystemAssigned identity
- WHEN Terraform applies the `azurerm_data_factory_linked_service_web` resource
- THEN a linked service named "LS_USGS_HTTP" appears in ADF Studio with status "Available"
- AND the linked service points to `https://earthquake.usgs.gov` with anonymous authentication

#### Scenario: ADF not deployed yet

- GIVEN `azurerm_data_factory.main` does not exist
- WHEN Terraform attempts to apply the linked service
- THEN Terraform fails with a dependency error before creating the resource

### Requirement: ADLS Gen2 Linked Service (Managed Identity)

The system MUST provision an `azurerm_data_factory_linked_service_azure_blob_storage` resource using the ADF system-assigned managed identity for authentication to ADLS Gen2.

#### Scenario: Linked service with MI auth

- GIVEN `azurerm_data_factory.main` has identity block with SystemAssigned
- AND `azurerm_role_assignment.adf_to_storage` grants Storage Blob Data Contributor on the storage account
- WHEN Terraform applies the linked service resource
- THEN a linked service named "LS_ADLS_GEN2" appears in ADF Studio with status "Available"
- AND it authenticates via Managed Identity (no access key or SAS token in connection string)

#### Scenario: MI role assignment missing

- GIVEN `azurerm_role_assignment.adf_to_storage` is not applied
- WHEN ADF attempts to use the linked service
- THEN the linked service connection test fails with an authorization error

### Requirement: Databricks Linked Service (MSI Auth, Serverless)

The system MUST provision an `azurerm_data_factory_linked_service_azure_databricks` resource using MSI authentication against the existing Databricks workspace. The linked service MUST NOT reference `existing_cluster_id` or `new_cluster_config` — compute is defined at the job level via `AzureDatabricksJob` activities. No PAT token SHALL be used.

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
