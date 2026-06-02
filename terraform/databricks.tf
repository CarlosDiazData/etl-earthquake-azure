resource "azurerm_databricks_workspace" "main" {
  name                        = var.databricks_workspace_name
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  sku                         = var.databricks_sku
  managed_resource_group_name = "${var.resource_group_name}-dbx"
  tags                        = var.tags
}

resource "databricks_notebook" "bronze_to_silver" {
  path     = "/Shared/earthquake-etl/01_bronze_to_silver"
  language = "PYTHON"
  source   = "${path.module}/../databricks/01_bronze_to_silver.py"
}

resource "databricks_notebook" "silver_to_gold" {
  path     = "/Shared/earthquake-etl/02_silver_to_gold"
  language = "PYTHON"
  source   = "${path.module}/../databricks/02_silver_to_gold.py"
}

data "databricks_node_type" "smallest" {
  local_disk = true
}

data "databricks_spark_version" "latest_lts" {
  long_term_support = true
}

resource "databricks_cluster" "job_cluster" {
  cluster_name  = "earthquake-etl-job-cluster"
  spark_version = data.databricks_spark_version.latest_lts.id
  node_type_id  = data.databricks_node_type.smallest.id
  autotermination_minutes = 30
  spark_conf = {
    "spark.databricks.delta.preview.enabled" = "true"
  }
  custom_tags = var.tags
}

resource "databricks_permissions" "cluster_usage" {
  cluster_id = databricks_cluster.job_cluster.id
  access_control {
    permission_level = "CAN_ATTACH_TO"
    group_name       = "users"
  }
}
