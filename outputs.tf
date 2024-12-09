# outputs.tf - Outputs for gdpr_jd-Compliant Azure OpenAI Solution

output "webapp_principal_id" {
  description = "Principal ID for Web App Managed Identity"
  value       = azurerm_linux_web_app.gdpr_jd_webapp.identity[0].principal_id
}

output "privacy_compliance_status" {
  description = "Indicates gdpr_jd Compliance Configuration Status"
  value = {
    data_encryption         = true
    network_isolation       = true
    consent_management      = var.gdpr_jd_consent_required
    data_retention_days     = var.data_retention_days
    contact_email           = var.privacy_contact_email
  }
}

output "cosmos_endpoint" {
    description = "Cosmos DB Account Endpoint"
    value       = azurerm_cosmosdb_account.gdpr_jd_cosmosdb_account.endpoint
    sensitive   = true
}   

output "cosmos_key" {
    description = "Cosmos DB Account Key"
    value       = azurerm_cosmosdb_account.gdpr_jd_cosmosdb_account.primary_key
    sensitive   = true
}

output "openai_endpoint" {
    description = "Azure OpenAI Service Endpoint"
    value       = azurerm_cognitive_account.gdpr_jd_openai.endpoint
    sensitive   = true
}

output "openai_subscription_key" {
    description = "Azure OpenAI Service Subscription Key"
    value       = azurerm_cognitive_account.gdpr_jd_openai.primary_access_key
    sensitive   = true
}

output "openai_resource_group" {
    description = "Azure OpenAI Service Resource Group"
    value       = azurerm_resource_group.gdpr_jd_openai_rg.name
}

output "front_door_hostname" {
    description = "Front Door Hostname for Secure Access"
    value       = azurerm_frontdoor.gdpr_jd_front_door.frontend_endpoint[0].host_name
}

output "key_vault_uri" {
    description = "Azure Key Vault URI for Encryption Keys and Secrets"
    value       = azurerm_key_vault.gdpr_jd_key_vault.vault_uri
}

output "webapp_url" {
    description = "URL for Chat Interface"
    value       = azurerm_linux_web_app.gdpr_jd_webapp.default_hostname
}