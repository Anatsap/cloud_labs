resource "azurerm_servicebus_namespace" "bus" {
  name                = "${var.project}-sbus"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
}
resource "azurerm_servicebus_queue" "queue" {
  name         = "car-writes"
  namespace_id = azurerm_servicebus_namespace.bus.id
}
resource "azurerm_container_app" "worker" {
  name                         = "${var.project}-worker"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  registry {
    server               = azurerm_container_registry.acr.login_server
    username             = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-admin-password"
  }

  secret {
    name  = "acr-admin-password"
    value = azurerm_container_registry.acr.admin_password
  }

  secret {
    name  = "database-url"
    value = "postgresql://${var.admin_username}:${random_password.db.result}@${azurerm_postgresql_flexible_server.postgres.fqdn}:5432/cardb?sslmode=require"
  }

  secret {
    name  = "sb-connection"
    value = azurerm_servicebus_namespace.bus.default_primary_connection_string
  }

  template {
    min_replicas = 0
    max_replicas = 3

    container {
      name    = "worker"
      image   = "${azurerm_container_registry.acr.login_server}/${var.project}-api:bootstrap"
      cpu     = 0.5
      memory  = "1Gi"
      command = ["python", "worker.py"]

      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name        = "SERVICEBUS_CONNECTION"
        secret_name = "sb-connection"
      }
      env {
        name  = "QUEUE_NAME"
        value = "car-writes"
      }
      env {
        name  = "REDIS_URL"
        value = "redis://${azurerm_container_app.redis.name}:6379/0"
      }
    }
  }
}
locals {
  queue_charts = [
    { x = 0, y = 0, title = "Long queue", res = azurerm_servicebus_namespace.bus.id, ns = "microsoft.servicebus/namespaces", metric = "ActiveMessages", agg = 3 },
    { x = 6, y = 0, title = "Репліки обробника", res = azurerm_container_app.worker.id, ns = "microsoft.app/containerapps", metric = "Replicas", agg = 3 },
    { x = 0, y = 4, title = "Requests for API", res = azurerm_container_app.app.id, ns = "microsoft.app/containerapps", metric = "Requests", agg = 1 },
  ]
}

resource "azurerm_portal_dashboard" "queue" {
  name                = "${var.project}-queue-dashboard"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          for i, c in local.queue_charts : tostring(i) => {
            position = { x = c.x, y = c.y, colSpan = 6, rowSpan = 4 }
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
                    }}}}}}}}}
    metadata = { model = {} }
  })
}