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

data "databricks_node_type" "smallest" {
  local_disk = true
}

data "databricks_spark_version" "latest_lts" {
  long_term_support = true
}

resource "databricks_cluster" "job_cluster" {
  cluster_name            = "earthquake-etl-job-cluster"
  spark_version           = data.databricks_spark_version.latest_lts.id
  node_type_id            = "Standard_DS3_v2"
  num_workers             = 1
  autotermination_minutes = 30
  data_security_mode      = "SINGLE_USER"
  spark_conf = {
    "spark.databricks.delta.preview.enabled"                                                    = "true"
    "spark.hadoop.fs.azure.account.auth.type.sadearthemovitdev.dfs.core.windows.net"            = "OAuth"
    "spark.hadoop.fs.azure.account.oauth.provider.type.sadearthemovitdev.dfs.core.windows.net"  = "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider"
    "spark.hadoop.fs.azure.account.oauth2.client.id.sadearthemovitdev.dfs.core.windows.net"     = var.azure_client_id
    "spark.hadoop.fs.azure.account.oauth2.client.secret.sadearthemovitdev.dfs.core.windows.net" = var.azure_client_secret
    "spark.hadoop.fs.azure.account.oauth2.client.endpoint.sadearthemovitdev.dfs.core.windows.net" = "https://login.microsoftonline.com/${var.azure_tenant_id}/oauth2/token"
  }
  custom_tags = var.tags
}
