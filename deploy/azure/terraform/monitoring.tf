resource "azurerm_monitor_metric_alert" "cpu_high" {
  name                = "${var.project}-cpu-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_container_app.app.id]
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.App/containerapps"
    metric_name      = "UsageNanoCores"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 350000000
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}