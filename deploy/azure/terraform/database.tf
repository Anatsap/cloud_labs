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

locals {
  charts = [
    { title = "Requests", res = azurerm_application_gateway.agw.id, ns = "microsoft.network/applicationgateways", metric = "TotalRequests", agg = 1 },
    { title = "Failed requests", res = azurerm_application_gateway.agw.id, ns = "microsoft.network/applicationgateways", metric = "FailedRequests", agg = 1 },
    { title = "Latency, ms", res = azurerm_application_gateway.agw.id, ns = "microsoft.network/applicationgateways", metric = "ApplicationGatewayTotalTime", agg = 4 },
    { title = "Unhealthy hosts", res = azurerm_application_gateway.agw.id, ns = "microsoft.network/applicationgateways", metric = "UnhealthyHostCount", agg = 4 },
    { title = "CPU, nanocores", res = azurerm_container_app.app.id, ns = "microsoft.app/containerapps", metric = "UsageNanoCores", agg = 4 },
    { title = "Memory, bytes", res = azurerm_container_app.app.id, ns = "microsoft.app/containerapps", metric = "WorkingSetBytes", agg = 4 },
  ]
}

resource "azurerm_portal_dashboard" "main" {
  name                = "${var.project}-dashboard"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          for i, c in local.charts : tostring(i) => {
            position = { x = (i % 2) * 6, y = floor(i / 2) * 4, colSpan = 6, rowSpan = 4 }
            metadata = {
              type = "Extension/HubsExtension/PartType/MonitorChartPart"
              inputs = [
                { name = "options", isOptional = true },
                { name = "sharedTimeRange", isOptional = true }
              ]
              settings = {
                content = {
                  options = {
                    chart = {
                      title = c.title
                      metrics = [{
                        resourceMetadata    = { id = c.res }
                        name                = c.metric
                        namespace           = c.ns
                        aggregationType     = c.agg
                        metricVisualization = { displayName = c.title }
                      }]
                      visualization = { chartType = 2 }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    metadata = { model = {} }
  })
}