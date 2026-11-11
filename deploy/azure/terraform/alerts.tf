resource "azurerm_monitor_metric_alert" "max_replicas" {
  name                = "${var.project}-max-replicas"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_container_app.app.id]
  description         = "Досягнуто максимальної кількості реплік"
  severity            = 2
  frequency           = "PT1M" 
  window_size         = "PT1M" 
  auto_mitigate       = true   

  criteria {
    metric_namespace = "Microsoft.App/containerapps"
    metric_name      = "Replicas"
    aggregation      = "Maximum"
    operator         = "GreaterThanOrEqual"
    threshold        = 4 
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}
