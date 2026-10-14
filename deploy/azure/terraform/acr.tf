resource "azurerm_container_registry" "acr" {
  name                = "carsregistrytsapiv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}
resource "terraform_data" "bootstrap_image" {
  triggers_replace = [
    filesha256("${var.app_path}/api.py"),
    filesha256("${var.app_path}/Dockerfile"),
    filesha256("${var.app_path}/requirements.txt")
  ]

  provisioner "local-exec" {
    command = <<-EOT
      az acr login --name ${azurerm_container_registry.acr.name}
      docker build -t ${azurerm_container_registry.acr.login_server}/${var.project}-api:bootstrap ${var.app_path}
      docker push ${azurerm_container_registry.acr.login_server}/${var.project}-api:bootstrap
    EOT
  }
}