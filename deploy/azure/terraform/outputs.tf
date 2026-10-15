output "service_url" {
  value = "http://${azurerm_public_ip.agw.ip_address}"
}

output "acr_repository" {
  value = azurerm_container_registry.acr.login_server
}

output "db_endpoint" {
  value = azurerm_postgresql_flexible_server.postgres.fqdn
}

output "client_id" {
  value = azurerm_user_assigned_identity.gh.client_id
}
output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}
output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}
output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}