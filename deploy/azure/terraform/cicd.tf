data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "gh" {
  name                = "${var.project}-github"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_federated_identity_credential" "gh" {
  name                = "github-main"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.gh.id
  issuer              = "https://token.actions.githubusercontent.com"
  audience            = ["api://AzureADTokenExchange"]
  subject             = "repo:${var.github_repo}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "gh_acr" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.gh.principal_id
}

resource "azurerm_role_assignment" "gh_app" {
  scope                = azurerm_container_app.app.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.gh.principal_id
}