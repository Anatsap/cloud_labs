resource "azurerm_container_app" "redis" {
  name                         = "${var.project}-redis"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  template {
    min_replicas = 1
    max_replicas = 1
    container {
      name   = "redis"
      image  = "redis:7.2-alpine"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = false
    transport        = "tcp"
    target_port      = 6379
    exposed_port     = 6379
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}