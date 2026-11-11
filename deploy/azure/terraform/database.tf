resource "random_password" "db" {
  length  = 24
  special = false
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "${var.project}-pg-server"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "15"
  administrator_login    = var.admin_username
  administrator_password = random_password.db.result
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"

  delegated_subnet_id           = azurerm_subnet.db.id
  private_dns_zone_id           = azurerm_private_dns_zone.pg.id
  public_network_access_enabled = false

  depends_on = [azurerm_private_dns_zone_virtual_network_link.pg]

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "db" {
  name      = "cardb"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "random_password" "admin" {
  length  = 20
  special = false
}



resource "azurerm_log_analytics_workspace" "logs" {
  name                = "${var.project}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_action_group" "email" {
  name                = "${var.project}-alerts"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "carsalert"

  email_receiver {
    name                    = "owner"
    email_address           = var.budget_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "errors_5xx" {
  name                = "${var.project}-5xx"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_container_app.app.id]
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.App/containerapps"
    metric_name      = "Requests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "statusCodeCategory"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}
