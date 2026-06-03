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
#     --scope "/subscriptions/<SUB>/resourceGroups/rg-earthquake-etl-dev/providers/Microsoft.Storage/storageAccounts/sadearthemovitdev"
