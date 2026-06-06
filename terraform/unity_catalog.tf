# Unity Catalog — Storage Credential y External Locations
# Reemplazan el spark_conf OAuth del cluster.

locals {
  # El access connector lo crea Azure automáticamente en el managed resource group del workspace
  databricks_access_connector_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/${var.resource_group_name}-dbx/providers/Microsoft.Databricks/accessConnectors/unity-catalog-access-connector"
}

resource "databricks_storage_credential" "main" {
  name = "sc-sadearthemovitdev"
  azure_managed_identity {
    access_connector_id = local.databricks_access_connector_id
  }
  comment = "Managed Identity para ADLS ${var.storage_account_name}"
}

resource "databricks_external_location" "bronze" {
  name            = "el-earthquake-bronze"
  url             = "abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.main.name
  skip_validation = true
  comment         = "Bronze — datos crudos USGS"
}

resource "databricks_external_location" "silver" {
  name            = "el-earthquake-silver"
  url             = "abfss://silver@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.main.name
  skip_validation = true
  comment         = "Silver — Delta limpio y enriquecido"
}

resource "databricks_external_location" "gold" {
  name            = "el-earthquake-gold"
  url             = "abfss://gold@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.main.name
  skip_validation = true
  comment         = "Gold — tablas dimensionales y fact"
}

# Grants para que el usuario humano pueda ver y usar los recursos en la UI
resource "databricks_grants" "storage_credential" {
  storage_credential = databricks_storage_credential.main.id
  grant {
    principal  = "carlosdiazdata@outlook.com"
    privileges = ["ALL_PRIVILEGES"]
  }
}

resource "databricks_grants" "external_location_bronze" {
  external_location = databricks_external_location.bronze.id
  grant {
    principal  = "carlosdiazdata@outlook.com"
    privileges = ["ALL_PRIVILEGES"]
  }
}

resource "databricks_grants" "external_location_silver" {
  external_location = databricks_external_location.silver.id
  grant {
    principal  = "carlosdiazdata@outlook.com"
    privileges = ["ALL_PRIVILEGES"]
  }
}

resource "databricks_grants" "external_location_gold" {
  external_location = databricks_external_location.gold.id
  grant {
    principal  = "carlosdiazdata@outlook.com"
    privileges = ["ALL_PRIVILEGES"]
  }
}

# ────────────────────────────────────────────────────────────────────
# UC Catalog + Schema for Gold tables
# ────────────────────────────────────────────────────────────────────

resource "databricks_catalog" "earthquake" {
  name             = "earthquake_etl"
  comment          = "Earthquake ETL — managed external tables"
  storage_root = "abfss://gold@${var.storage_account_name}.dfs.core.windows.net/managed/"
}

resource "databricks_schema" "gold" {
  catalog_name = databricks_catalog.earthquake.name
  name         = "gold"
  comment      = "Star schema dimensional tables — dim_* and fact_*"
}

# Grants: el Service Principal necesita permisos para crear/reemplazar tablas
resource "databricks_grants" "catalog_earthquake" {
  catalog = databricks_catalog.earthquake.name
  grant {
    principal  = data.azurerm_client_config.current.client_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA"]
  }
  grant {
    principal  = "carlosdiazdata@outlook.com"
    privileges = ["ALL_PRIVILEGES"]
  }
}

resource "databricks_grants" "schema_gold" {
  schema = "${databricks_catalog.earthquake.name}.${databricks_schema.gold.name}"
  grant {
    principal  = data.azurerm_client_config.current.client_id
    privileges = ["USE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY", "EXECUTE"]
  }
  grant {
    principal  = "carlosdiazdata@outlook.com"
    privileges = ["ALL_PRIVILEGES"]
  }
}
