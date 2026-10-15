resource "azurerm_container_app_environment" "env" {
  name                           = "${var.project}-container-env"
  resource_group_name            = azurerm_resource_group.rg.name
  location                       = azurerm_resource_group.rg.location
  infrastructure_subnet_id       = azurerm_subnet.app.id
  internal_load_balancer_enabled = true
  lifecycle {
    ignore_changes = [infrastructure_resource_group_name]
  }
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
}

resource "azurerm_container_app" "app" {
  name                         = "${var.project}-api"
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
    name  = "jwt-secret"
    value = random_password.jwt.result
  }
  secret {
    name  = "admin-password"
    value = random_password.admin.result
  }

  template {
    min_replicas = 1
    container {
      name   = "api"
      image  = "${azurerm_container_registry.acr.login_server}/${var.project}-api:bootstrap"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name        = "JWT_SECRET_KEY"
        secret_name = "jwt-secret"
      }
      env {
        name        = "ADMIN_PASSWORD"
        secret_name = "admin-password"
      }
    }
  }

  ingress {
    allow_insecure_connections = true
    external_enabled           = true
    target_port                = 5000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [terraform_data.bootstrap_image]

  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
      workload_profile_name,
    ]
  }
}