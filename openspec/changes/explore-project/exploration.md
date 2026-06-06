## Exploration: Full Project Overview — etl-earthquake-azure

### Current State

The project is a **migration** of an existing AWS-based earthquake ETL pipeline (`etl-earthquake-aws`) to Azure. It ingests earthquake data from the USGS API, processes it through a Medallion architecture (Bronze → Silver → Gold), and stores analytical dimensional models.

**What's implemented (and deployed):**

- **Infrastructure as Code**: 7 Terraform files covering the full Azure stack — Resource Group, ADLS Gen2 storage, Databricks workspace + job cluster + notebook uploads, Data Factory + linked services + pipeline + schedule trigger, Unity Catalog storage credentials/external locations, and outputs
- **PySpark Transformations**: 2 complete notebooks handling bronze→silver (flatten, cast, validate, dedup, enrich) and silver→gold (Star Schema: dim_date, dim_location, dim_magnitude, dim_event_type, fact_earthquake_events)
- **CI/CD**: GitHub Actions workflow that runs `terraform validate`, `plan`, and `apply` on push to `main` or `develop`
- **SDD Process**: 3 archived changes completed via the SDD workflow (dev-infra-readiness, adf-objects-via-code, develop-branch-cicd)
- **Deployment**: Infrastructure already deployed to Azure — resources exist (RG, Storage Account, Data Factory, Databricks workspace)

**Deployment details (from `deploy-data.md`):**
| Resource | Value |
|----------|-------|
| Subscription | `cb575e24-3643-41ce-b9a6-f809fb7ac2b9` |
| Resource Group | `rg-earthquake-etl-dev` |
| Storage Account | `sadearthemovitdev` |
| Data Factory | `adf-earthquake-etl-dev` |
| Databricks Workspace | `adb-7405606254634054.14.azuredatabricks.net` |
| PAT Token | Created (expires ~2026-09-01) |
| GitHub Secrets | All 5 configured (ARM_* + DATABRICKS_TOKEN) |

### Architecture Summary

```
USGS API (HTTP CSV/GeoJSON)
        │
        ▼
ADF Copy Data ────────────────── ADLS /bronze/raw/
(HTTP source → JSON sink)
        │
        ▼
ADF Databricks Notebook
(01_bronze_to_silver) ────────── ADLS /silver/cleansed/ (Delta)
        │                        - Flatten GeoJSON → flat columns
        │                        - Type casting & validation
        │                        - Dedup by event_id
        │                        - Feature engineering (categories, hemispheres)
        ▼
ADF Databricks Notebook
(02_silver_to_gold) ──────────── ADLS /gold/dimensional/ (Parquet)
                                 - dim_date (calendar attributes)
                                 - dim_location (unique coords + hemisphere)
                                 - dim_magnitude (Micro→Great categories)
                                 - dim_event_type (event_type + magType)
                                 - fact_earthquake_events (measures)
```

**Tech stack:**

| Layer | Technology |
|-------|-----------|
| Infrastructure | Terraform (AzureRM + Databricks providers), backend on Azure Storage |
| Storage | ADLS Gen2 (bronze/silver/gold containers) |
| Orchestration | Azure Data Factory (Pipeline + Schedule trigger every 6h) |
| Transformation | Databricks PySpark (Unity Catalog, Delta Lake) |
| CI/CD | GitHub Actions (plan on PR, apply on push) |

### SDD Changes Completed (Archived)

Three changes fully through the SDD cycle:

1. **dev-infra-readiness** (2026-06-02) — Bootstrap: outputs.tf, .gitignore, fixed Databricks provider auth (Azure SP instead of PAT), added remote state backend, fixed deploy.yml with `-var-file`, created `dev.tfvars`
2. **adf-objects-via-code** (2026-06-03) — Migrated 7 ADF resources from manual creation to Terraform: LS_USGS_HTTP, LS_ADLS_GEN2, LS_DATABRICKS, DS_USGS_GEOJSON, DS_ADLS_BRONZE_JSON, PL_MasterPipeline (3 activities), TR_Schedule_6h
3. **develop-branch-cicd** (2026-06-03) — CI/CD expanded to support `main` + `develop` branches; PR triggers plan-only; `develop` branch created

**Active specs** (source of truth):
- `openspec/specs/adf-linked-services/spec.md` — 3 requirements (HTTP, ADLS with MI, Databricks with MSI no PAT)
- `openspec/specs/adf-pipeline-orchestration/spec.md` — 4 requirements (HTTP dataset, JSON sink, pipeline with 3 sequential activities, 6h trigger)

### Key Files and Their Roles

| File | Role |
|------|------|
| `terraform/main.tf` | Providers (azurerm, databricks), resource group, state backend |
| `terraform/storage.tf` | ADLS Gen2 storage account + bronze/silver/gold containers |
| `terraform/databricks.tf` | Workspace, job cluster (`Standard_DS3_v2`), notebook uploads, OAuth config for ADLS |
| `terraform/datafactory.tf` | Data Factory, 3 linked services, 2 datasets, pipeline (3 activities), schedule trigger (6h) |
| `terraform/unity_catalog.tf` | Storage credential (managed identity), 3 external locations, grants |
| `terraform/variables.tf` | 8 variables (4 without defaults: rg name, storage, df, databricks names) |
| `terraform/outputs.tf` | 6 outputs (rg name, storage, blob endpoint, db workspace URL/ID, df name/identity) |
| `terraform/dev.tfvars` | Dev environment variable values |
| `databricks/01_bronze_to_silver.py` | 171-line PySpark: flattens GeoJSON, casts types, validates ranges, dedup, enriches (magnitude category, hemisphere, region extraction, time attributes) → writes Delta |
| `databricks/02_silver_to_gold.py` | 148-line PySpark: builds Star Schema (4 dimensions + fact table), writes Parquet via saveAsTable |
| `.github/workflows/deploy.yml` | Terraform fmt/init/validate/plan/apply on push to main/develop, plan-only on PR |
| `plan.md` | Original migration plan — architecture, component list, implementation order |
| `README.md` | Project docs — architecture diagram, stack, structure, prerequisites, deploy instructions |
| `deploy-data.md` | **NOTE: in .gitignore** — actual deployment values (subscription IDs, SP credentials, tokens) |
| `openspec/config.yaml` | SDD configuration — context, phase rules |
| `openspec/specs/` | Main specs (adf-linked-services, adf-pipeline-orchestration) |
| `.gitignore` | Terraform state/plans, Python cache, IDE files, sensitive doc files |

### Data Flow (Notebook Level)

**01_bronze_to_silver.py:**
1. Read multiline JSON from ADLS Bronze (`/bronze/raw/`)
2. Explode `features` array → flatten properties + geometry.coordinates
3. Cast: epoch ms → Timestamp, mag → Double, depth → Double, tsunami → Boolean
4. Validate: magnitude (-2..10), lat (-90..90), lon (-180..180), depth (0..1000), timestamps/event_id non-null
5. Dedup: window by `event_id`, order by `updated_timestamp_utc DESC`, keep row_number = 1
6. Enrich: magnitude_category (Micro→Great), depth_category (Shallow/Intermediate/Deep), hemisphere (NS/EW), year/month/day/hour/day_of_week, country extraction from `place`
7. Write Delta to Silver, partitioned by year/month

**02_silver_to_gold.py:**
1. Read Delta from Silver
2. Generate dim_date: date range from data + 30 days, with FullDate/Year/Quarter/Month/DayOfWeek/IsWeekend
3. Build dim_location: distinct lat/lon/place/country/region/hemisphere, monotonically_increasing_id
4. Build dim_magnitude: 8 static categories (Micro→Great + Unknown)
5. Build dim_event_type: distinct event_type + magType combinations
6. Build fact_earthquake_events: inner joins on all dims, dropDuplicates by EventID
7. Write all 5 tables as Parquet via saveAsTable

### Remaining Work

From `plan.md` and codebase analysis:

**Phase: Post-deployment validation**
- Debug the full pipeline end-to-end (manual ADF trigger run)
- Verify Copy Data activity works with USGS API
- Verify Databricks notebooks execute and write to ADLS correctly
- Verify schedule trigger fires at correct intervals

**Phase: Git integration**
- Connect the ADF to the Git repo (as noted in plan.md step 4)

**Phase: Future enhancements (planned but not started)**
- **Snowflake integration** — `plan.md` explicitly says "No incluye Snowflake — pendiente para después". The README shows Gold → Snowflake as a future arrow in the architecture diagram
- **Monitoring & alerting** — No CloudWatch/Azure Monitor equivalent configured yet
- **OIDC auth** — Currently using Service Principal + client secret; OIDC is a documented future improvement from the dev-infra-readiness exploration
- **Multiple environments** — Only `dev` exists; no `prod` tfvars or environment promotion workflow
- **Unity Catalog schema/table creation** — The UC external locations exist, but there are no `databricks_schema` or `databricks_table` resources to register tables in Unity Catalog
- **Production-grade CI/CD** — No deployment approvals, no artifact promotion, shared tfstate key acknowledged risk

**Potential improvements (observed):**
- The `dim_location` table uses `F.monotonically_increasing_id()` which is non-deterministic — IDs will change between runs, breaking SCD tracking
- No test framework exists (`openspec/config.yaml` confirms: `tdd: false`, `test_command: ""`)
- The OAuth `spark_conf` in `databricks.tf` hardcodes the storage account `sadearthemovitdev` — this should be parameterized via `var.storage_account_name` (it uses the hardcoded name in 5 different spark config keys)
- The `databricks_cluster` Spark config references the hardcoded dev storage account name — if the env changes, these config values break
- Notebooks use `overwrite` mode — no incremental/append pattern for Silver→Gold; each run rebuilds the entire Star Schema

### Risks and Observations

| # | Risk/Observation | Severity | Detail |
|---|-----------------|----------|--------|
| 1 | **Hardcoded storage account in spark_conf** | Medium | `databricks.tf` lines 43-50 hardcode `sadearthemovitdev` in 5 spark config keys instead of using `var.storage_account_name`. If storage account name changes, this breaks silently |
| 2 | **Monotonically increasing ID for dim_location** | Low-Medium | `F.monotonically_increasing_id()` is non-deterministic across runs — same location gets different LocationKey each time. This breaks any downstream foreign key references if used beyond single-run analytics |
| 3 | **Overwrite mode for Gold** | Low | Both notebooks use `mode("overwrite")`. For Bronze→Silver this is reasonable (full refresh), but Silver→Gold regenerates all dimension keys each run. This is fine for dev but not production-grade |
| 4 | **No incremental processing** | Low | Pipeline does full re-read and re-process every 6 hours, even if only new data exists. Acceptable for the data volume (USGS earthquake events ~20k max) |
| 5 | **PAT token lifecycle** | Medium | The Databricks PAT token in `deploy-data.md` expires ~2026-09-01. Must be manually rotated. The ADF Linked Service uses MSI (no PAT), but there are references to `DATABRICKS_TOKEN` in GitHub Secrets that need rotation |
| 6 | **No monitoring/alerting** | Medium | If the pipeline fails (USGS API down, cluster failure, etc.), there's no automated detection. Someone must check manually |
| 7 | **Single environment** | Low | Only `dev` exists. No staging/prod isolation. The `env` var is defined but not used differently |
| 8 | **State backend bootstrapped but fragile** | Low | State backend exists and works, but if the state storage account is ever deleted or corrupted, recovery is manual |
| 9 | **No Unity Catalog schema/table resources** | Low-Medium | UC external locations are configured, but notebooks use `saveAsTable` which creates tables in the `default` schema. No formal UC schema/catalog/table resources in Terraform |
| 10 | **`deploy-data.md` in .gitignore** | Info | Deployment credentials are excluded from Git, which is correct, but means they exist only in a local file. Should be documented elsewhere (e.g., password manager, Key Vault) |

### Ready for Proposal

Yes — this exploration provides a complete picture of the project. The next recommended SDD change would depend on the user's priority:

- **Short-term**: Debug the full pipeline end-to-end (verify ADF → Databricks → ADLS works)
- **Medium-term**: Parameterize the hardcoded storage account in `databricks.tf`, add monitoring/alerting
- **Long-term**: Snowflake integration, OIDC auth, multi-environment deployment
