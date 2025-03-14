locals {
  base_name = "${var.project_name}-${var.short_name_location}"
}

################
# Virtual Network
################
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.base_name}"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_subnet" "capp" {
  name                 = "sn-capp"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_capp_address_space

  delegation {
    name = "capp"

    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet" "web" {
  name                 = "sn-web"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_web_address_space

  delegation {
    name = "web-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "sn-pe"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_endpoints_address_space
}

################
# Key Vault
################
resource "azurerm_key_vault" "main" {
  name                        = "kv-${local.base_name}"
  location                    = var.location
  resource_group_name         = data.azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  enable_rbac_authorization   = true

  sku_name = "standard"
}

resource "azurerm_role_assignment" "kv_secret_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

################
# MSSQL
################
resource "random_password" "mssql_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "azurerm_key_vault_secret" "mssql_password" {
  name         = "sqlAdminPassword"
  value        = random_password.mssql_password.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_secret_officer]
}

resource "azurerm_key_vault_secret" "mssql_username" {
  name         = "appUserPassword"
  value        = var.mssql_username
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_secret_officer]
}

resource "azurerm_mssql_server" "main" {
  name                          = "mssql-srv-${local.base_name}"
  resource_group_name           = data.azurerm_resource_group.main.name
  location                      = var.location
  version                       = "12.0"
  administrator_login           = var.mssql_username
  administrator_login_password  = random_password.mssql_password.result
  public_network_access_enabled = false
}

resource "azurerm_mssql_database" "app" {
  name         = "todo"
  server_id    = azurerm_mssql_server.main.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  max_size_gb  = 2
  sku_name     = "S0"
}

resource "azurerm_key_vault_secret" "database_todo_connectionstring" {
  name         = "connectionStringKey"
  value        = "Server=${azurerm_mssql_server.main.fully_qualified_domain_name}; Database=${azurerm_mssql_database.app.name}; User=${var.mssql_username};Password=${random_password.mssql_password.result};"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_secret_officer]
}

################
# MSSQL Private Endpoint
################
resource "azurerm_private_endpoint" "my_terraform_endpoint" {
  name                = "pe-mssql-${local.base_name}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "private-serviceconnection"
    private_connection_resource_id = azurerm_mssql_server.main.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.my_terraform_dns_zone.id]
  }
}

resource "azurerm_private_dns_zone" "my_terraform_dns_zone" {
  name                = "privatelink.database.windows.net"
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "my_terraform_vnet_link" {
  name                  = "vnet-link"
  resource_group_name   = data.azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.my_terraform_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

################
# Monitoring
################
resource "azurerm_log_analytics_workspace" "main" {
  name                = "logs-${local.base_name}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "main" {
  name                = "appinsights-${local.base_name}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  application_type    = "web"
}

################
# Container App
################
resource "azurerm_user_assigned_identity" "capp" {
  name                = "mid-capp-${local.base_name}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
}

resource "azurerm_role_assignment" "capp_api_secret_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.capp.principal_id
}

resource "azurerm_container_app_environment" "main" {
  name                               = "cae-${local.base_name}"
  location                           = var.location
  resource_group_name                = data.azurerm_resource_group.main.name
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.main.id
  infrastructure_subnet_id           = azurerm_subnet.capp.id
  infrastructure_resource_group_name = "cae-${local.base_name}-infra"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 1
    maximum_count         = 10
  }
}

resource "azurerm_container_app" "api" {
  name                         = "ca-api-${local.base_name}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"

  ingress {
    target_port = 8080
    traffic_weight {
      percentage = 100
      latest_revision = true
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.capp.id]
  }

  secret {
    name  = "registrypassword"
    value = var.container_registry_password
  }

  registry {
    server               = var.container_registry_server
    username             = var.container_registry_username
    password_secret_name = "registrypassword"
  }

  secret {
    name                = "connectionstringkey"
    identity            = azurerm_user_assigned_identity.capp.id
    key_vault_secret_id = azurerm_key_vault_secret.database_todo_connectionstring.id
  }

  template {
    min_replicas = 1
    max_replicas = 10
    container {
      name   = "api"
      image  = "acrmfolabsmicsi242.azurecr.io/csharp_api:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "AZURE_KEY_VAULT_ENDPOINT"
        value = azurerm_key_vault.main.vault_uri
      }
      env {
        name        = "AZURE_SQL_CONNECTION_STRING_KEY"
        secret_name = "connectionstringkey"
      }
    }
  }

  depends_on = [azurerm_role_assignment.capp_api_secret_user]
}

################
# App Service
################
resource "azurerm_service_plan" "main" {
  name                = "asp-${local.base_name}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "S1"
}

resource "azurerm_linux_web_app" "api" {
  name                = "api-${local.base_name}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id

  site_config {
    application_stack {
      docker_image_name        = "react_app:latest"
      docker_registry_url      = "https://${var.container_registry_server}"
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }

  app_settings = {
    VITE_API_BASE_URL                          = azurerm_container_app.api.latest_revision_fqdn
    VITE_APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
  }
}

resource "azurerm_app_service_virtual_network_swift_connection" "api" {
  app_service_id = azurerm_linux_web_app.api.id
  subnet_id      = azurerm_subnet.web.id
}

################
# Traffic Manager
################
resource "azurerm_traffic_manager_profile" "main" {
  name                   = "tm-${local.base_name}"
  resource_group_name    = data.azurerm_resource_group.main.name
  traffic_routing_method = "Performance"

  dns_config {
    relative_name = "tm-${local.base_name}"
    ttl           = 100
  }

  monitor_config {
    protocol                     = "HTTP"
    port                         = 80
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 9
    tolerated_number_of_failures = 3
  }
}

# resource "azurerm_traffic_manager_azure_endpoint" "web" {
#   name               = "web"
#   profile_id         = azurerm_traffic_manager_profile.main.id
#   target_resource_id = azurerm_linux_web_app.api.id
# }

################
# DNS
################
resource "azurerm_dns_cname_record" "tm" {
  name                = "mfolabs-app"
  zone_name           = var.dns_zone_name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 300
  record              = azurerm_traffic_manager_profile.main.fqdn
}
