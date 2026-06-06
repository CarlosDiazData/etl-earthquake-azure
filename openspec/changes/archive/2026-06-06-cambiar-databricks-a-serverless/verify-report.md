# Verify Report: cambiar-databricks-a-serverless

**Date**: 2026-06-06
**Status**: ⚠️ WARNING — 2 warnings, 1 pre-existing spec deviation, 1 blocked check
**Mode**: Read-only verification (no terraform state inspection — no deployment confirmed)

---

## Summary

| # | Requirement | Source | Result | Evidence |
|---|------------|--------|--------|----------|
| 1.1 | `databricks_job.bronze_to_silver` deployed serverless | `databricks-jobs/spec.md` R1 | ✅ PASS | `terraform/databricks.tf:32-58` — job exists, notebook_task, no cluster blocks |
| 1.2 | `databricks_job.silver_to_gold` deployed serverless | `databricks-jobs/spec.md` R2 | ✅ PASS | `terraform/databricks.tf:60-86` — job exists, notebook_task, no cluster blocks |
| 1.3 | Job names match spec | `databricks-jobs/spec.md` R1/R2 scenarios | ✅ PASS | Names: "earthquake-bronze-to-silver", "earthquake-silver-to-gold" |
| 1.4 | Environment blocks with pip dependencies | `databricks-jobs/spec.md` R1 Sc2 | ✅ PASS | Both jobs have `environment { environment_key = "shared" }` blocks |
| 1.5 | No spark_conf block (no OAuth) | `databricks-jobs/spec.md` R1 Sc3 | ✅ PASS | No `spark_conf` in either job; auth via UC MI |
| 1.6 | `performance_target` set | `databricks-jobs/spec.md` R2 Sc1 | ⚠️ WARNING | `PERFORMANCE_OPTIMIZED` used; spec says "cost optimization", design chose performance. See W1. |
| 2.1 | `databricks_cluster.job_cluster` destroyed | Task 1.3 / apply-progress | ✅ PASS | No `databricks_cluster`, `data.databricks_node_type`, or `data.databricks_spark_version` in any `.tf` file |
| 3.1 | Linked service: MSI auth, no PAT | `adf-linked-services/spec.md` MR1 Sc1 | ✅ PASS | `msi_workspace_id` set; no PAT token |
| 3.2 | Linked service: no `existing_cluster_id` | `adf-linked-services/spec.md` MR1 Sc1 | ✅ PASS | `existing_cluster_id` absent from linked service |
| 3.3 | Linked service: no `new_cluster_config` | `adf-linked-services/spec.md` MR1 Sc1 | ⚠️ WARNING | `new_cluster_config` present — AzureRM v4 provider constraint. See W2. |
| 3.4 | Linked service: `adb_domain` with https:// | Task description | ✅ PASS | `adb_domain = "https://adb-7405606254634054.14.azuredatabricks.net"` |
| 3.5 | Linked service: `adb_domain` dynamic vs hardcoded | `design.md` snippet | ℹ️ MINOR | Hardcoded URL instead of `workspace_url` attribute — works, but differs from design. |
| 4.1 | Pipeline: DatabricksJob activities with jobId | `adf-pipeline-orchestration/spec.md` MR1 Sc1 | ✅ PASS | Activities "Job_Bronze_To_Silver" and "Job_Silver_To_Gold" — type `DatabricksJob`, jobId references `databricks_job.*.id` |
| 4.2 | Pipeline: sequential dependency chain | `adf-pipeline-orchestration/spec.md` MR1 Sc1 | ✅ PASS | Copy → Job_Bronze_To_Silver → Job_Silver_To_Gold via `dependsOn` with `Succeeded` conditions |
| 4.3 | Pipeline: Copy activity preserved | `adf-pipeline-orchestration/spec.md` MR1 Sc1 | ✅ PASS | "Copy_USGS_To_Bronze" activity present |
| 4.4 | Pipeline: no `adls_account`/`adls_container` params | Task 3.3 | ✅ PASS | Only `bronze_path`, `silver_path`, `gold_path` in jobParameters |
| 5.1 | Notebook 01: no `adls_account`/`adls_container` widgets | Task 4.1 | ✅ PASS | Only `bronze_path` and `silver_path` widgets; `STORAGE_ACCOUNT` hardcoded |
| 5.2 | Notebook 02: no `adls_account` widget | Task 4.2 | ✅ PASS | Only `silver_path` and `gold_path` widgets; `STORAGE_ACCOUNT` hardcoded |
| 5.3 | Notebooks: ABFSS paths use hardcoded storage | Task 4.1/4.2 | ✅ PASS | Both build paths as `abfss://{container}@{STORAGE_ACCOUNT}.dfs.core.windows.net/...` |
| 6.1 | UC catalog `earthquake_etl` exists | Task description | ✅ PASS | `terraform/unity_catalog.tf:78-82` — `databricks_catalog.earthquake` with name "earthquake_etl" |
| 6.2 | UC schema `gold` under `earthquake_etl` | Task description | ✅ PASS | `terraform/unity_catalog.tf:84-88` — `databricks_schema.gold` |
| 6.3 | SP grants on catalog | Task description | ✅ PASS | SP has USE_CATALOG, USE_SCHEMA, CREATE_SCHEMA, MANAGE on catalog |
| 6.4 | SP grants on schema `gold` | Task description | ✅ PASS | SP has USE_SCHEMA, CREATE_TABLE, SELECT, MODIFY, EXECUTE, MANAGE on schema |
| 7.1 | Storage credential uses ADF MI (main spec) | `databricks-uc-auth/spec.md` R1 | ❌ FAIL (pre-existing) | Uses Databricks access connector MI, not ADF MI. See C1. |
| 7.2 | External locations for bronze/silver/gold | `databricks-uc-auth/spec.md` R2 | ✅ PASS | `el-earthquake-bronze`, `el-earthquake-silver`, `el-earthquake-gold` exist |
| 8.1 | Pipeline executed successfully | Task 5.3 / user confirmation | 🔲 BLOCKED | Not deployed; `terraform apply` not executed in this session |
| 9.1 | `terraform validate` passes | Task 5.2 | ✅ PASS | Confirmed in apply-progress; `terraform fmt` applied |

---

## Warnings

### W1: `performance_target` mismatch with spec
- **Spec says**: "the `performance_target` optimizes cost over execution speed" (`databricks-jobs/spec.md` Silver-to-Gold Sc1)
- **Implementation**: `performance_target = "PERFORMANCE_OPTIMIZED"` (both jobs)
- **Impact**: Jobs optimize for execution speed, not cost. Higher DBU consumption per run.
- **Resolution**: If cost is priority, change to `COST_OPTIMIZED`. If performance was the deliberate choice (per design.md), update the spec scenario to match.

### W2: `new_cluster_config` in linked service
- **Delta spec says**: "The linked service omits `existing_cluster_id` and `new_cluster_config` from its JSON definition" (`adf-linked-services/spec.md` MR1 Sc1)
- **Implementation**: `new_cluster_config` block present with minimal `Standard_DS3_v2` / 1 worker config.
- **Root cause**: AzureRM provider v4 schema requires one of `existing_cluster_id`, `instance_pool`, or `new_cluster_config`. There is no "serverless" option in the provider.
- **Runtime impact**: None — AzureDatabricksJob activities resolve compute at the job level via `jobId`. The `new_cluster_config` in the linked service is ignored at runtime for job activities.
- **Resolution**: Accept as provider limitation. Document in spec delta that `new_cluster_config` may be present but is inert.

---

## Critical Findings

### C1 (Pre-existing): Storage credential uses wrong identity
- **Main spec requires**: `databricks_storage_credential` using ADF's managed identity, named "adf-mi-credential" (`databricks-uc-auth/spec.md` R1)
- **Actual**: `databricks_storage_credential.main` named "sc-sadearthemovitdev", uses Databricks access connector MI (`unity_catalog.tf:9-15`)
- **Impact**: Spec-implementation divergence on auth model. Access connector MI works but is not what the spec describes. The Databricks-managed access connector needs RBAC on ADLS Gen2 (Storage Blob Data Contributor).
- **Scope**: Pre-existing — UC resources were provisioned before this serverless migration change. Not in scope to fix here, but should be tracked as separate spec alignment work.

---

## Blocked

### B1: End-to-end pipeline execution
- **Task 5.3**: "Trigger ADF pipeline end-to-end; verify bronze→silver→gold completes in < 3 min"
- **Status**: Not deployed. No `terraform apply` was performed in this implementation session.
- **Verification**: Requires deployment + trigger. Can't be verified from code alone.

---

## Code Review Notes

| File | Lines | Changes Verified |
|------|-------|-----------------|
| `terraform/databricks.tf` | 86 | 2 job resources added, cluster removed, no data sources for node/spark |
| `terraform/datafactory.tf` | 213 | Linked service: existing_cluster_id removed, new_cluster_config added (provider req). Pipeline: Notebook → DatabricksJob activities, jobId refs |
| `terraform/unity_catalog.tf` | 113 | UC catalog, schema, grants — all present (pre-existing) |
| `terraform/variables.tf` | 78 | azure_client_id/secret retained (provider auth dependency, skipped per task 5.1) |
| `databricks/01_bronze_to_silver.py` | 170 | Widgets changed: adls_account/adls_container removed; STORAGE_ACCOUNT hardcoded |
| `databricks/02_silver_to_gold.py` | 156 | Widgets changed: adls_account removed; STORAGE_ACCOUNT hardcoded; CREATE TABLE IF NOT EXISTS for UC registration |

---

## Verdict

**Overall**: ⚠️ Pass with Warnings

- 11/12 implementation tasks completed (1 skipped intentionally)
- 1 blocked (deployment/execution)
- Core migration (cluster→serverless jobs, ADF Notebook→AzureDatabricksJob, notebook auth) is correctly implemented
- 2 warnings: spec-implementation mismatch on `performance_target` and `new_cluster_config` (provider constraint)
- 1 pre-existing spec deviation on storage credential identity (not in scope)
