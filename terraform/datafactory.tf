resource "azurerm_data_factory" "main" {
  name                = var.data_factory_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "adf_to_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "adf_to_databricks" {
  scope                = azurerm_databricks_workspace.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_factory.main.identity[0].principal_id
}

# NOTA: El SP (data.azurerm_client_config.current.object_id) necesita
# Storage Blob Data Contributor sobre el storage account para que el cluster
# de Databricks pueda leer/escribir vía OAuth.
#
# Terraform NO puede asignar este rol porque el SP no tiene permisos de
# User Access Administrator. Se asigna UNA SOLA VEZ manualmente:
#
#   az role assignment create \
#     --assignee "<SP_CLIENT_ID>" \
#     --role "Storage Blob Data Contributor" \
#   --scope "/subscriptions/<SUB>/resourceGroups/rg-earthquake-etl-dev/providers/Microsoft.Storage/storageAccounts/sadearthemovitdev"

# ---------------------------------------------------------------------------
# Phase 1: Linked Services
# ---------------------------------------------------------------------------

resource "azurerm_data_factory_linked_custom_service" "usgs" {
  name                 = "LS_USGS_HTTP_V2"
  data_factory_id      = azurerm_data_factory.main.id
  type                 = "HttpServer"
  type_properties_json = jsonencode({
    url                = "https://earthquake.usgs.gov/fdsnws/event/1/"
    authenticationType = "Anonymous"
  })
}

resource "azurerm_data_factory_linked_service_azure_blob_storage" "adls" {
  name                 = "LS_ADLS_GEN2"
  data_factory_id      = azurerm_data_factory.main.id
  use_managed_identity = true
  service_endpoint     = azurerm_storage_account.main.primary_blob_endpoint
}

resource "azurerm_data_factory_linked_service_azure_databricks" "databricks" {
  name                = "LS_DATABRICKS"
  data_factory_id     = azurerm_data_factory.main.id
  msi_workspace_id    = azurerm_databricks_workspace.main.id
  adb_domain          = azurerm_databricks_workspace.main.workspace_url
  existing_cluster_id = databricks_cluster.job_cluster.id
}

# ---------------------------------------------------------------------------
# Phase 2: Datasets
# ---------------------------------------------------------------------------

resource "azurerm_data_factory_dataset_http" "usgs" {
  name                = "DS_USGS_GEOJSON"
  data_factory_id     = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_custom_service.usgs.name
  relative_url        = "query?format=geojson&minmagnitude=2.5&limit=20000&orderby=time"
  request_method      = "GET"
}

resource "azurerm_data_factory_dataset_json" "bronze" {
  name                = "DS_ADLS_BRONZE_JSON"
  data_factory_id     = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.adls.name

  azure_blob_storage_location {
    container = "bronze"
    path      = "raw/"
    filename  = "usgs_earthquakes.json"
  }
}

# ---------------------------------------------------------------------------
# Phase 2: Pipeline
# ---------------------------------------------------------------------------

resource "azurerm_data_factory_pipeline" "master" {
  name            = "PL_MasterPipeline"
  data_factory_id = azurerm_data_factory.main.id

  activities_json = jsonencode([
    {
      name      = "Copy_USGS_To_Bronze"
      type      = "Copy"
      dependsOn = []
      policy = {
        timeout                = "0:30:00"
        retry                  = 1
        retryIntervalInSeconds = 30
      }
      inputs = [
        {
          referenceName = "DS_USGS_GEOJSON"
          type          = "DatasetReference"
        }
      ]
      outputs = [
        {
          referenceName = "DS_ADLS_BRONZE_JSON"
          type          = "DatasetReference"
        }
      ]
      source = {
        type = "HttpSource"
      }
      sink = {
        type = "JsonSink"
      }
    },
    {
      name = "Notebook_Bronze_To_Silver"
      type = "DatabricksNotebook"
      dependsOn = [
        {
          activity             = "Copy_USGS_To_Bronze"
          dependencyConditions = ["Succeeded"]
        }
      ]
      policy = {
        timeout                = "0:30:00"
        retry                  = 1
        retryIntervalInSeconds = 30
      }
      typeProperties = {
        notebookPath = "/Shared/earthquake-etl/01_bronze_to_silver"
        baseParameters = {
          adls_container = "bronze"
          adls_account   = var.storage_account_name
          bronze_path    = "raw/"
          silver_path    = "cleansed/"
        }
        linkedServiceName = {
          referenceName = "LS_DATABRICKS"
          type          = "LinkedServiceReference"
        }
      }
    },
    {
      name = "Notebook_Silver_To_Gold"
      type = "DatabricksNotebook"
      dependsOn = [
        {
          activity             = "Notebook_Bronze_To_Silver"
          dependencyConditions = ["Succeeded"]
        }
      ]
      policy = {
        timeout                = "0:30:00"
        retry                  = 1
        retryIntervalInSeconds = 30
      }
      typeProperties = {
        notebookPath = "/Shared/earthquake-etl/02_silver_to_gold"
        baseParameters = {
          adls_account = var.storage_account_name
          silver_path  = "cleansed/"
          gold_path    = "dimensional/"
        }
        linkedServiceName = {
          referenceName = "LS_DATABRICKS"
          type          = "LinkedServiceReference"
        }
      }
    }
  ])

  depends_on = [
    azurerm_data_factory_dataset_http.usgs,
    azurerm_data_factory_dataset_json.bronze,
    azurerm_data_factory_linked_service_azure_databricks.databricks,
  ]
}

# ---------------------------------------------------------------------------
# Phase 2: Schedule Trigger
# ---------------------------------------------------------------------------

resource "azurerm_data_factory_trigger_schedule" "every_6h" {
  name            = "TR_Schedule_6h"
  data_factory_id = azurerm_data_factory.main.id
  pipeline_name   = azurerm_data_factory_pipeline.master.name
  frequency       = "Hour"
  interval        = 6
  activated       = true
}
