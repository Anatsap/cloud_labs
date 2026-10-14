resource "azurerm_resource_group" "rg" {
  name     = "${var.project}-resources"
  location = var.region
}