# Configure Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# Data source for client configuration
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "openai-chat-rg"
  location = "West Europe"  # Choose GDPR compliant region

  tags = {
    Environment = "Production"
    DataPrivacy = "GDPR"
  }
}

# Key Vault for storing secrets
resource "azurerm_key_vault" "kv" {
  name                = "openai-chat-kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id          = data.azurerm_client_config.current.tenant_id
  sku_name           = "premium"

  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = []  # Configure allowed IP ranges
  }
}

# Azure OpenAI Service
resource "azurerm_cognitive_account" "openai" {
  name                = "openai-service"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "OpenAI"
  sku_name           = "S0"

  custom_subdomain_name = "openai-chat"
  
  network_acls {
    default_action = "Deny"
    ip_rules       = []  # Configure allowed IP ranges
  }

  identity {
    type = "SystemAssigned"
  }
}

# OpenAI Model Deployment
resource "azurerm_cognitive_deployment" "gpt" {
  name                 = "gpt-35-turbo"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  model {
    format  = "OpenAI"
    name    = "gpt-35-turbo"
    version = "0301"
  }

  scale {
    type = "Standard"
  }
}

# App Service Plan
resource "azurerm_service_plan" "plan" {
  name                = "openai-chat-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type            = "Linux"
  sku_name           = "P1v2"
}

resource "azurerm_cosmosdb_account" "db" {
  name                = "openai-chat-cosmosdb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }
}

# Web App
resource "azurerm_linux_web_app" "webapp" {
  name                = "openai-chat-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.plan.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true
    application_stack {
      node_version = "18-lts"
    }

    cors {
      allowed_origins = ["https://your-domain.com"]
    }
  }

  app_settings = {
    "COSMOS_DB_ENDPOINT"      = azurerm_cosmosdb_account.db.endpoint
    "OPENAI_ENDPOINT"         = azurerm_cognitive_account.openai.endpoint
    "KEYVAULT_ENDPOINT"       = azurerm_key_vault.kv.vault_uri
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
  }
}

# Front Door
resource "azurerm_cdn_frontdoor_profile" "fd" {
  name                = "openai-chat-fd"
  resource_group_name = azurerm_resource_group.rg.name
  sku_name           = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "endpoint" {
  name                     = "openai-chat-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id
}

# Front Door Origin Group
resource "azurerm_cdn_frontdoor_origin_group" "origin" {
  name                     = "webapp-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id
  session_affinity_enabled = true

  health_probe {
    protocol            = "Https"
    interval_in_seconds = 100
    path               = "/"
    request_type       = "HEAD"
  }

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }
}

# Front Door Origin
resource "azurerm_cdn_frontdoor_origin" "webapp" {
  name                          = "webapp-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.origin.id
  
  enabled                       = true
  host_name                     = azurerm_linux_web_app.webapp.default_hostname
  http_port                     = 80
  https_port                    = 443
  origin_host_header           = azurerm_linux_web_app.webapp.default_hostname
  priority                      = 1
  weight                        = 1000
  certificate_name_check_enabled = true
}

# Front Door Route
resource "azurerm_cdn_frontdoor_route" "default" {
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.origin.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.webapp.id]
  
  enabled                       = true
  forwarding_protocol          = "HttpsOnly"
  https_redirect_enabled       = true
  patterns_to_match            = ["/*"]
  supported_protocols         = ["Http", "Https"]

  cdn_frontdoor_custom_domain_ids = []  # Add custom domains if needed
  
  link_to_default_domain         = true

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled          = true
    content_types_to_compress    = ["text/html", "text/javascript", "text/css"]
  }
}

# WAF Policy for Front Door
resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  name                = "openaichatwaf"
  resource_group_name = azurerm_resource_group.rg.name
  sku_name           = azurerm_cdn_frontdoor_profile.fd.sku_name
  enabled            = true
  mode              = "Prevention"

  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
    action  = "Block"

    override {
      rule_group_name = "PROTOCOL-ATTACK"
      rule {
        rule_id = "942200"
        action  = "Block"
        enabled = true
      }
    }
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  custom_rule {
    name     = "BlockHighRiskCountries"
    enabled  = true
    priority = 1
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator          = "GeoMatch"
      negation_condition = false
      match_values      = ["CN", "RU"] # Add countries you want to block
    }
  }
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "openai-chat-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                = "PerGB2018"
  retention_in_days   = 90  # GDPR compliance
}

# Application Insights
resource "azurerm_application_insights" "appinsights" {
  name                = "openai-chat-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.logs.id
  application_type    = "web"
}

# Virtual Network for network isolation
resource "azurerm_virtual_network" "vnet" {
  name                = "openai-chat-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]

  subnet {
    name           = "webapp-subnet"
    address_prefix = "10.0.1.0/24"
  }
}

# Private DNS Zone for Cosmos DB
resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

# Private Endpoint for Cosmos DB
resource "azurerm_private_endpoint" "cosmos" {
  name                = "cosmos-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_virtual_network.vnet.subnet.*.id[0]

  private_service_connection {
    name                           = "cosmos-private-link"
    private_connection_resource_id = azurerm_cosmosdb_account.db.id
    is_manual_connection          = false
    subresource_names            = ["SQL"]
  }

  private_dns_zone_group {
    name                 = "cosmos-dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos.id]
  }
}