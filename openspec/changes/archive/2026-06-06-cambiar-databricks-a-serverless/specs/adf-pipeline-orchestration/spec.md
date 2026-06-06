# Delta for ADF Pipeline Orchestration

## MODIFIED Requirements

### Requirement: PL_MasterPipeline with Three Sequential Activities

The system MUST provision an `azurerm_data_factory_pipeline` resource containing exactly three activities in sequence: Copy Data (HTTP → Bronze JSON), AzureDatabricksJob 01 (bronze_to_silver via jobId), and AzureDatabricksJob 02 (silver_to_gold via jobId). Failure in any activity MUST halt downstream execution via `depends_on` in the activities JSON.
(Previously: used Notebook activities referencing notebook paths directly)

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
