variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
  default     = "dev"
}

variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "storage_account_name" {
  description = "Storage Account name (globally unique, lowercase alphanumeric)"
  type        = string
}

variable "data_factory_name" {
  description = "Data Factory name"
  type        = string
}

variable "databricks_workspace_name" {
  description = "Databricks Workspace name"
  type        = string
}

variable "databricks_sku" {
  description = "Databricks pricing tier"
  type        = string
  default     = "premium"
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    Project     = "earthquake-etl"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

variable "azure_client_id" {
  description = "Azure Service Principal client ID (must match ARM_CLIENT_ID GitHub Secret)"
  type        = string
  sensitive   = true
}

variable "azure_client_secret" {
  description = "Azure Service Principal client secret (must match ARM_CLIENT_SECRET GitHub Secret)"
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  description = "Azure Service Principal tenant ID (must match ARM_TENANT_ID GitHub Secret)"
  type        = string
  sensitive   = true
}

variable "azure_subscription_id" {
  description = "Azure Subscription ID (must match ARM_SUBSCRIPTION_ID GitHub Secret)"
  type        = string
  sensitive   = true
}

variable "databricks_token" {
  description = "Databricks PAT token for provider auth (fallback when Azure SP lacks workspace perms)"
  type        = string
  sensitive   = true
  default     = null
}
