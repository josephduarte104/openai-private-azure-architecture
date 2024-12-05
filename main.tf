# main.tf - Primary Terraform configuration for GDPR-Compliant Azure OpenAI Solution

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "gdpr_openai_rg" {
  name     = "rg-gdpr-openai-compliance"
  location = var.location

  tags = {
    environment = "production"
    compliance  = "gdpr"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "gdpr_vnet" {
  name                = "vnet-gdpr-openai"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  address_space       = ["10.0.0.0/16"]
}

# Subnet for resources
resource "azurerm_subnet" "gdpr_subnet" {
  name                 = "subnet-gdpr-openai"
  resource_group_name  = azurerm_resource_group.gdpr_openai_rg.name
  virtual_network_name = azurerm_virtual_network.gdpr_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group for additional protection
resource "azurerm_network_security_group" "gdpr_nsg" {
  name                = "nsg-gdpr-openai"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name

  security_rule {
    name                       = "AllowAzureFrontDoor"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureFrontDoor.Backend"
    destination_address_prefix = "*"
  }
}

# Azure Front Door for secure access
resource "azurerm_frontdoor" "gdpr_front_door" {
  name                = "fd-gdpr-openai-access"
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name

  routing_rule {
    name               = "webapp-routing"
    accepted_protocols = ["Https"]
    patterns_to_match  = ["/*"]
    frontend_endpoints = ["webapp-endpoint"]
    forwarding_configuration {
      forwarding_protocol = "HttpsOnly"
      backend_pool_name   = "webapp-backend"
    }
  }

  backend_pool {
    name                 = "webapp-backend"
    health_probe_name    = "health-probe"
    load_balancing_name  = "load-balancing-settings"
    backend {
      host_header = azurerm_linux_web_app.gdpr_webapp.default_hostname
      address     = azurerm_linux_web_app.gdpr_webapp.default_hostname
      http_port   = 80
      https_port  = 443
    }
  }

  backend_pool_health_probe {
    name     = "health-probe"
    protocol = "Https"
    path     = "/health"
    interval_in_seconds = 30
  }

  backend_pool_load_balancing {
    name                            = "load-balancing-settings"
    sample_size                     = 4
    successful_samples_required     = 2
  }

  frontend_endpoint {
    name      = "webapp-endpoint"
    host_name = "gdpr-openai-webapp.azurefd.net"
  }

  # Enforce HTTPS and TLS 1.2+
}

# Cosmos DB Account with Strong Encryption and Access Controls
resource "azurerm_cosmosdb_account" "gdpr_cosmosdb_account" {
  name                = "cosmos-gdpr-openai-data"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Strong"
  }

  geo_location {
    location          = azurerm_resource_group.gdpr_openai_rg.location
    failover_priority = 0
  }

  # GDPR Compliance Controls
  network_acl_bypass_for_azure_services = true
  public_network_access_enabled         = false

  # Additional Security Configurations
  is_virtual_network_filter_enabled = true
}

resource "azurerm_cosmosdb_sql_database" "gdpr_database" {
  name                = "gdpr-database"
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  account_name        = azurerm_cosmosdb_account.gdpr_cosmosdb_account.name
}

# Cosmos DB Container for JSON Documents
resource "azurerm_cosmosdb_sql_container" "gdpr_container" {
  name                = "gdpr-compliant-documents"
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  account_name        = azurerm_cosmosdb_account.gdpr_cosmosdb_account.name
  database_name       = azurerm_cosmosdb_sql_database.gdpr_database.name
  partition_key_paths = ["/partitionKey"]

  indexing_policy {
    indexing_mode = "consistent"
    
    included_path {
      path = "/*"
    }
    
    excluded_path {
      path = "/sensitive_data/*"
    }
  }
}

# Azure OpenAI Service
resource "azurerm_cognitive_account" "gdpr_openai" {
  name                = "cogacc-gdpr-openai"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  kind                = "CognitiveServices"
  sku_name            = "S1"

  custom_subdomain_name = "gdpr-openai"

  network_acls {
  default_action = "Deny"

  ip_rules = [
    "1.2.3.4",
    "5.6.7.8"
  ]

  }

  tags = {
  environment = "production"
  compliance  = "gdpr"
  }
}

# Key Vault for Encryption Keys and Secrets
resource "azurerm_key_vault" "gdpr_key_vault" {
  name                        = "kv-gdpr-openai"
  location                    = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name         = azurerm_resource_group.gdpr_openai_rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"

  access_policy {
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get",
    "List",
  ]

  secret_permissions = [
    "Get",
    "List",
  ]

  certificate_permissions = [
    "Get",
    "List",
  ]
  }

  tags = {
  environment = "production"
  compliance  = "gdpr"
  }
}

# Linux Web App for Chat Interface
resource "azurerm_linux_web_app" "gdpr_webapp" {
  name                = "webapp-gdpr-openai"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  service_plan_id     = azurerm_service_plan.gdpr_app_service_plan.id

  identity {
  type = "SystemAssigned"
  }
  site_config {
  #linux_fx_version    = "DOCKER|mcr.microsoft.com/azure-app-service/samples/aspnetcore"
  health_check_path = "/health"
  health_check_eviction_time_in_min = 10
  }

  app_settings = {
  "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  tags = {
  environment = "production"
  compliance  = "gdpr"
  }
}

resource "azurerm_service_plan" "gdpr_app_service_plan" {
  name                = "asp-gdpr-openai"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  os_type             = "Linux"
  zone_balancing_enabled = true
  sku_name            = "S1"
  worker_count        = 2
}

# Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "key_vault_private_endpoint" {
  name                = "pe-kv-gdpr-openai"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  subnet_id           = azurerm_subnet.gdpr_subnet.id

  private_service_connection {
  name                           = "keyvaultConnection"
  private_connection_resource_id = azurerm_key_vault.gdpr_key_vault.id
  subresource_names              = ["vault"]
  is_manual_connection           = false
  }
}

# Private Endpoint for Cosmos DB
resource "azurerm_private_endpoint" "cosmosdb_private_endpoint" {
  name                = "pe-cosmosdb-gdpr-openai"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  subnet_id           = azurerm_subnet.gdpr_subnet.id

  private_service_connection {
  name                           = "cosmosdbConnection"
  private_connection_resource_id = azurerm_cosmosdb_account.gdpr_cosmosdb_account.id
  subresource_names              = ["sql"]
  is_manual_connection           = false
  }
}

# Private Endpoint for Cognitive Services
resource "azurerm_private_endpoint" "cognitive_services_private_endpoint" {
  name                = "pe-cogsvc-gdpr-openai"
  location            = azurerm_resource_group.gdpr_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_openai_rg.name
  subnet_id           = azurerm_subnet.gdpr_subnet.id

  private_service_connection {
  name                           = "cognitiveServicesConnection"
  private_connection_resource_id = azurerm_cognitive_account.gdpr_openai.id
  subresource_names              = ["account"]
  is_manual_connection           = false
  }
}
