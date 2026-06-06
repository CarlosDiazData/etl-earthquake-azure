resource "azurerm_databricks_workspace" "main" {
  name                        = var.databricks_workspace_name
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  sku                         = var.databricks_sku
  managed_resource_group_name = "${var.resource_group_name}-dbx"
  tags                        = var.tags
}

resource "databricks_directory" "etl_folder" {
  path = "/Shared/earthquake-etl"
}

resource "databricks_notebook" "bronze_to_silver" {
  path       = "/Shared/earthquake-etl/01_bronze_to_silver"
  language   = "PYTHON"
  source     = "${path.module}/../databricks/01_bronze_to_silver.py"
  depends_on = [databricks_directory.etl_folder]
}

resource "databricks_notebook" "silver_to_gold" {
  path       = "/Shared/earthquake-etl/02_silver_to_gold"
  language   = "PYTHON"
  source     = "${path.module}/../databricks/02_silver_to_gold.py"
  depends_on = [databricks_directory.etl_folder]
}

# ────────────────────────────────────────────────────────────────────
# Databricks Jobs (serverless) — replaces classic databricks_cluster
# ────────────────────────────────────────────────────────────────────

resource "databricks_job" "bronze_to_silver" {
  name = "earthquake-bronze-to-silver"

  task {
    task_key = "cleanse_earthquake_data"

    notebook_task {
      notebook_path = databricks_notebook.bronze_to_silver.path
      base_parameters = {
        silver_path = "cleansed/"
      }
    }
  }

  environment {
    environment_key = "shared"
    spec {
      client       = "1"
      dependencies = []
    }
  }

  max_concurrent_runs = 1
  performance_target  = "PERFORMANCE_OPTIMIZED"

  depends_on = [databricks_notebook.bronze_to_silver]
}

resource "databricks_job" "silver_to_gold" {
  name = "earthquake-silver-to-gold"

  task {
    task_key = "build_star_schema"

    notebook_task {
      notebook_path = databricks_notebook.silver_to_gold.path
      base_parameters = {
        gold_path = "dimensional/v2/"
      }
    }
  }

  environment {
    environment_key = "shared"
    spec {
      client       = "1"
      dependencies = []
    }
  }

  max_concurrent_runs = 1
  performance_target  = "PERFORMANCE_OPTIMIZED"

  depends_on = [databricks_notebook.silver_to_gold]
}
