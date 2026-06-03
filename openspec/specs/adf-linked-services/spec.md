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

### Requirement: Databricks Linked Service (MSI Auth, No PAT)

The system MUST provision an `azurerm_data_factory_linked_service_azure_databricks` resource using MSI authentication against the existing Databricks workspace, referencing the existing job cluster. No PAT token SHALL be used.

#### Scenario: Linked service with MSI and existing cluster

- GIVEN `azurerm_databricks_workspace.main` is deployed
- AND `databricks_cluster.job_cluster` exists
- AND `azurerm_role_assignment.adf_to_databricks` grants Contributor on the workspace
- WHEN Terraform applies the Databricks linked service resource
- THEN a linked service named "LS_DATABRICKS" appears in ADF Studio with status "Available"
- AND it authenticates via Managed Identity targeting the workspace ID
- AND the linked service references the existing cluster `earthquake-etl-job-cluster` by ID
- AND no PAT token is stored in the linked service connection string
