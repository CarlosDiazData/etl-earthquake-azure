output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "ADLS Gen2 storage account name"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint for ADLS Gen2 storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "databricks_workspace_url" {
  description = "Databricks workspace URL"
  value       = azurerm_databricks_workspace.main.workspace_url
}

output "databricks_workspace_id" {
  description = "Databricks workspace resource ID"
  value       = azurerm_databricks_workspace.main.workspace_id
}

output "databricks_workspace_location" {
  description = "Databricks workspace Azure region"
  value       = azurerm_databricks_workspace.main.location
}

output "data_factory_name" {
  description = "Data Factory name"
  value       = azurerm_data_factory.main.name
}

output "data_factory_identity_principal_id" {
  description = "Data Factory system-assigned managed identity principal ID"
  value       = azurerm_data_factory.main.identity[0].principal_id
}
