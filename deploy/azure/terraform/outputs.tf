output "service_url" {
  value = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "acr_repository" {
  value = azurerm_container_registry.acr.login_server
}

output "db_endpoint" {
  value = azurerm_postgresql_flexible_server.postgres.fqdn
}