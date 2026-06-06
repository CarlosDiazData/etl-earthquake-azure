# Databricks Jobs Specification

## Purpose

Define Terraform `databricks_job` resources that run the ETL notebooks using serverless compute, replacing the classic `databricks_cluster.job_cluster` and ADF Notebook activities.

## Requirements

### Requirement: Bronze-to-Silver Job

The system MUST provision a `databricks_job` resource running `01_bronze_to_silver.py` via `notebook_task` on serverless compute. The job SHALL include an `environment` block for PySpark dependencies.

#### Scenario: Job deploys with serverless compute

- GIVEN `databricks_job` resource has no `existing_cluster_id` or `job_cluster_key`
- WHEN Terraform applies the resource
- THEN a job named "earthquake-bronze-to-silver" appears in Databricks Workflows UI
- AND the job runs on serverless compute (no cluster configuration required)
- AND the job references `01_bronze_to_silver.py` as its notebook task

#### Scenario: Environment block provides pip dependencies

- GIVEN the job includes an `environment` block with `pypi` dependencies
- WHEN the job executes
- THEN the specified pip packages install before notebook execution

#### Scenario: Spark conf absent

- GIVEN the job has no `spark_conf` block (no OAuth secrets)
- WHEN Terraform validates the resource
- THEN no validation warning is raised
- AND auth uses the workspace managed identity via Unity Catalog

### Requirement: Silver-to-Gold Job

The system MUST provision a `databricks_job` resource running `02_silver_to_gold.py` via `notebook_task`. The job SHALL set `performance_target` for cost optimization and include an `environment` block matching the bronze-to-silver job.

#### Scenario: Job deploys with performance target

- GIVEN `databricks_job` resource includes a `performance_target` block
- WHEN Terraform applies the resource
- THEN a job named "earthquake-silver-to-gold" appears in Databricks Workflows UI
- AND the job runs on serverless compute
- AND the `performance_target` optimizes cost over execution speed

#### Scenario: Both jobs share environment spec

- GIVEN both jobs define identical `environment` blocks
- WHEN either job executes
- THEN the same pip dependency set is installed in both runtimes
