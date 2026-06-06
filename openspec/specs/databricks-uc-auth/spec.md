# Databricks Unity Catalog Auth Specification

## Purpose

Define Unity Catalog external location authentication via Managed Identity, replacing Spark conf OAuth (`spark.hadoop.fs.azure.account.oauth2.*`).

## Requirements

### Requirement: Storage Credential for ADF Managed Identity

The system MUST provision a `databricks_storage_credential` resource using ADF's managed identity to authenticate to ADLS Gen2.

#### Scenario: Storage credential created

- GIVEN ADF's managed identity has Storage Blob Data Contributor on the storage account
- WHEN Terraform applies `databricks_storage_credential`
- THEN a credential named "adf-mi-credential" appears in Unity Catalog
- AND the credential uses Managed Identity (Azure) authentication
- AND the credential's managed identity ID matches ADF's principal ID

#### Scenario: Missing role assignment

- GIVEN ADF's managed identity lacks the Storage Blob Data Contributor role
- WHEN the storage credential exists but a notebook attempts to access ADLS
- THEN access fails with an authorization error in the run logs

### Requirement: External Locations for Medallion Containers

The system MUST provision `databricks_external_location` resources for the bronze, silver, and gold ADLS Gen2 containers using the storage credential.

#### Scenario: External locations created

- GIVEN the `adf-mi-credential` storage credential exists
- WHEN Terraform applies `databricks_external_location` resources
- THEN locations named "adls-bronze-ext-loc", "adls-silver-ext-loc", and "adls-gold-ext-loc" appear in Unity Catalog
- AND each location points to the corresponding container: `abfss://{container}@{storage}.dfs.core.windows.net/`

#### Scenario: Notebook reads via UC path

- GIVEN external locations exist in Unity Catalog
- WHEN a notebook reads a file via the UC location path (e.g., `/Volumes/external/adls-bronze/...`)
- THEN the read authenticates via the managed identity credential
- AND no `spark.hadoop.fs.azure.account.oauth2.*` configs exist in the Spark session
