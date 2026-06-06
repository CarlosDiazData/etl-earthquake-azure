# ADF Pipeline Orchestration Specification

## Purpose

Define the Terraform-managed ADF pipeline (PL_MasterPipeline) and schedule trigger that orchestrate the ETL process: copy GeoJSON from USGS API to ADLS Bronze, then execute Databricks notebooks for Silver (Delta) and Gold (Parquet Star Schema) transformations.

## Requirements

### Requirement: HTTP GeoJSON Source Dataset

The system MUST provision an `azurerm_data_factory_dataset_http` resource linked to LS_USGS_HTTP, pointing to the USGS GeoJSON endpoint at relative URL `/fdsnws/event/1/query?format=geojson&minmagnitude=4`.

#### Scenario: Dataset created

- GIVEN `azurerm_data_factory_linked_service_web.LS_USGS_HTTP` exists
- WHEN Terraform applies the HTTP dataset resource
- THEN a dataset named "DS_USGS_GEOJSON" appears in ADF Studio linked to LS_USGS_HTTP
- AND the relative URL includes `format=geojson` and `minmagnitude=4` query parameters

### Requirement: JSON Sink Dataset (ADLS Bronze)

The system MUST provision an `azurerm_data_factory_dataset_json` resource linked to LS_ADLS_GEN2, pointing to the bronze container at path `raw/`. The dataset SHALL use JSON format (not delimited text), matching the GeoJSON input.

#### Scenario: Dataset created

- GIVEN `azurerm_data_factory_linked_service_azure_blob_storage.LS_ADLS_GEN2` exists
- WHEN Terraform applies the JSON dataset resource
- THEN a dataset named "DS_ADLS_BRONZE_JSON" appears in ADF Studio
- AND it writes to the bronze container at path `raw/`
- AND the dataset format is JSON (not delimited text or Parquet)

### Requirement: PL_MasterPipeline with Three Sequential Activities

The system MUST provision an `azurerm_data_factory_pipeline` resource containing exactly three activities in sequence: Copy Data (HTTP → Bronze JSON), AzureDatabricksJob 01 (bronze_to_silver via jobId), and AzureDatabricksJob 02 (silver_to_gold via jobId). Failure in any activity MUST halt downstream execution via `depends_on` in the activities JSON.

#### Scenario: Full pipeline execution via job references

- GIVEN DS_USGS_GEOJSON, DS_ADLS_BRONZE_JSON, LS_DATABRICKS, and both `databricks_job` resources exist
- WHEN the pipeline is triggered
- THEN Copy Data reads GeoJSON from USGS API and writes it to ADLS Bronze at `raw/`
- AFTER Copy Data succeeds, AzureDatabricksJob 01 executes referencing `jobId` of the bronze-to-silver job
- AND job 01 reads JSON from Bronze, flattens and transforms it, writes Delta to Silver
- AFTER job 01 succeeds, AzureDatabricksJob 02 executes referencing `jobId` of the silver-to-gold job
- AND job 02 reads Delta from Silver, builds Star Schema, writes Parquet to Gold

#### Scenario: Copy Data fails

- GIVEN the USGS API is unreachable or returns an error
- WHEN the Copy Data activity fails
- THEN AzureDatabricksJob 01 MUST NOT execute
- AND AzureDatabricksJob 02 MUST NOT execute
- AND the pipeline status is "Failed"

#### Scenario: Bronze-to-silver job fails

- GIVEN Bronze JSON data is empty or malformed
- WHEN AzureDatabricksJob 01 (bronze_to_silver) fails
- THEN AzureDatabricksJob 02 MUST NOT execute
- AND the pipeline status is "Failed"
- AND Silver and Gold remain unchanged

### Requirement: Schedule Trigger (Every 6 Hours)

The system MUST provision an `azurerm_data_factory_trigger_schedule` resource with 6-hour recurrence, associated with PL_MasterPipeline. The trigger SHALL NOT retroactively fire for missed intervals on initial deployment.

#### Scenario: Trigger fires at scheduled intervals

- GIVEN PL_MasterPipeline exists
- WHEN the schedule trigger is created with 6-hour recurrence
- THEN the trigger fires at 00:00, 06:00, 12:00, and 18:00 UTC daily
- AND each trigger execution starts PL_MasterPipeline

#### Scenario: No retroactive execution on deployment

- GIVEN Terraform applies the trigger for the first time at 14:00 UTC
- WHEN the trigger is activated
- THEN it does NOT fire for the 12:00 UTC missed interval
- AND the first execution occurs at 18:00 UTC
