resource "azurerm_subnet" "agw" {
  name                 = "agw-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_public_ip" "agw" {
  name                = "${var.project}-agw-ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "agw" {
  name                = "${var.project}-agw"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }
    ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "gw-ip"
    subnet_id = azurerm_subnet.agw.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  backend_address_pool {
    name         = "app"
    ip_addresses = [azurerm_container_app_environment.env.static_ip_address]
  }

  probe {
    name                = "health"
    protocol            = "Http"
    host                = azurerm_container_app.app.ingress[0].fqdn
    path                = "/health"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    match {
      status_code = ["200"]
    }
  }

  backend_http_settings {
    name                  = "app"
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 30
    host_name             = azurerm_container_app.app.ingress[0].fqdn
    probe_name            = "health"
  }

  http_listener {
    name                           = "listener"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "listener"
    backend_address_pool_name  = "app"
    backend_http_settings_name = "app"
  }
}