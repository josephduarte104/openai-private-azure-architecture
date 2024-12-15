# main.tf - Primary Terraform configuration for gdpr_jd-Compliant Azure OpenAI Solution

# Terraform block specifying required version and providers
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.9.0"
    }
  }
}

# Configure the Microsoft Azure Provider with specific features
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

# Data source to retrieve information about the current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group for the GDPR-compliant Azure OpenAI solution
resource "azurerm_resource_group" "gdpr_jd_openai_rg" {
  name     = "rg-gdpr_jd-openai-compliance"
  location = var.location

  tags = {
    environment = "production"
    compliance  = "gdpr_jd"
  }
}

# Virtual Network configuration
resource "azurerm_virtual_network" "gdpr_jd_vnet" {
  name                = "vnet-gdpr_jd-openai"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  address_space       = ["10.0.0.0/16"]
}

# Subnet configuration within the Virtual Network
resource "azurerm_subnet" "gdpr_jd_subnet" {
  name                 = "subnet-gdpr_jd-openai"
  resource_group_name  = azurerm_resource_group.gdpr_jd_openai_rg.name
  virtual_network_name = azurerm_virtual_network.gdpr_jd_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group for additional protection
resource "azurerm_network_security_group" "gdpr_jd_nsg" {
  name                = "nsg-gdpr_jd-openai"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name

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

### Front Door Configuration ###
resource "azurerm_cdn_frontdoor_profile" "gdpr_jd_front_door_profile" {
  name                = "fdgdprjdopenaiaccessi-profile"
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "gdpr_jd_front_door_endpoint" {
  name                = "fdgdprjdopenaiaccessi-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.gdpr_jd_front_door_profile.id
}

resource "azurerm_cdn_frontdoor_origin_group" "gdpr_jd_front_door_origin_group" {
  name                = "fdgdprjdopenaiaccessi-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.gdpr_jd_front_door_profile.id
  health_probe {
    path               = "/health"
    protocol           = "Https"
    interval_in_seconds = 30
  }
  load_balancing {
    sample_size                 = 4
    successful_samples_required = 2
  }
}

resource "azurerm_cdn_frontdoor_origin" "gdpr_jd_front_door_origin" {
  name                = "fdgdprjdopenaiaccessi-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.gdpr_jd_front_door_origin_group.id
  #host_name                     = azurerm_windows_web_app.gdpr_jd_webapp.default_hostname
  host_name                     = azurerm_linux_web_app.gdpr_jd_webapp.default_hostname
  https_port                    = 443
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "gdpr_jd_front_door_route" {
  name                        = "fdgdprjdopenaiaccessi-route"
  cdn_frontdoor_origin_ids    = [azurerm_cdn_frontdoor_origin.gdpr_jd_front_door_origin.id]
  cdn_frontdoor_endpoint_id   = azurerm_cdn_frontdoor_endpoint.gdpr_jd_front_door_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.gdpr_jd_front_door_origin_group.id
  supported_protocols         = ["Http", "Https"]
  patterns_to_match           = ["/*"]
  forwarding_protocol         = "HttpsOnly"
  https_redirect_enabled      = true
}

# Cosmos DB Account with Strong Encryption and Access Controls
resource "azurerm_cosmosdb_account" "gdpr_jd_cosmosdb_account" {
  name                = "cosmosgdprjdopenaidata"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Strong"
  }

  geo_location {
    location          = azurerm_resource_group.gdpr_jd_openai_rg.location
    failover_priority = 0
  }
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "gdpr_jd_database" {
  name                = "gdpr_jddatabase"
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  account_name        = azurerm_cosmosdb_account.gdpr_jd_cosmosdb_account.name
}

# Cosmos DB Container for JSON Documents
resource "azurerm_cosmosdb_sql_container" "gdpr_jd_container" {
  name                = "gdpr_jdcompliant-documents"
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  account_name        = azurerm_cosmosdb_account.gdpr_jd_cosmosdb_account.name
  database_name       = azurerm_cosmosdb_sql_database.gdpr_jd_database.name
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
resource "azurerm_cognitive_account" "gdpr_jd_openai" {
  name                = "cogacc-gdprjdopenai"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  kind                = "CognitiveServices"
  sku_name            = "S0"

  custom_subdomain_name = "gdprjdopenai"

  network_acls {
    default_action = "Deny"
    ip_rules       = []  # Configure allowed IP ranges
  }

  identity {
    type = "SystemAssigned"
  }
}

# Key Vault for Encryption Keys and Secrets
resource "azurerm_key_vault" "gdpr_jd_key_vault" {
  name                        = "kv-gpdjd-openai"
  location                    = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name         = azurerm_resource_group.gdpr_jd_openai_rg.name
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
    compliance  = "gdpr_jd"
  }
}

# Linux Web App for Chat Interface
resource "azurerm_linux_web_app" "gdpr_jd_webapp" {
  name                = "webappgpdrjdopenai"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  service_plan_id     = azurerm_service_plan.gdpr_jd_app_service_plan.id

  identity {
    type = "SystemAssigned"
  }
  site_config {
    health_check_path = "/health"
    health_check_eviction_time_in_min = 10
  }

  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }

  tags = {
    environment = "production"
    compliance  = "gdpr_jd"
  }
}

# App Service Plan for the Linux Web App
resource "azurerm_service_plan" "gdpr_jd_app_service_plan" {
  name                = "asp-gdpr_jd-openai"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  os_type             = "Linux"
  zone_balancing_enabled = false
  sku_name            = "S1"
  worker_count        = 1
}

# Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "key_vault_private_endpoint" {
  name                = "pe-kvgpdrjdopenai"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  subnet_id           = azurerm_subnet.gdpr_jd_subnet.id

  private_service_connection {
    name                           = "keyvaultConnection"
    private_connection_resource_id = azurerm_key_vault.gdpr_jd_key_vault.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }
}

# Private Endpoint for Cosmos DB
resource "azurerm_private_endpoint" "cosmosdb_private_endpoint" {
  name                = "pe-cosmosdb-gdpr_jd-openai"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  subnet_id           = azurerm_subnet.gdpr_jd_subnet.id

  private_service_connection {
    name                           = "cosmosdbConnection"
    private_connection_resource_id = azurerm_cosmosdb_account.gdpr_jd_cosmosdb_account.id
    subresource_names              = ["sql"]
    is_manual_connection           = false
  }
}

# Private Endpoint for Cognitive Services
resource "azurerm_private_endpoint" "cognitive_services_private_endpoint" {
  name                = "pe-cogsvc-gdpr_jd-openai"
  location            = azurerm_resource_group.gdpr_jd_openai_rg.location
  resource_group_name = azurerm_resource_group.gdpr_jd_openai_rg.name
  subnet_id           = azurerm_subnet.gdpr_jd_subnet.id

  private_service_connection {
    name                           = "cognitiveServicesConnection"
    private_connection_resource_id = azurerm_cognitive_account.gdpr_jd_openai.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }
}
