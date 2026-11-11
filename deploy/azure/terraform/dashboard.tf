resource "azurerm_monitor_diagnostic_setting" "agw" {
  name                       = "agw-logs"
  target_resource_id         = azurerm_application_gateway.agw.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }
}

locals {
  app_id = azurerm_container_app.app.id
  agw_id = azurerm_application_gateway.agw.id
  p95_query = "AzureDiagnostics | where Category == 'ApplicationGatewayAccessLog' | summarize p95_ms = percentile(timeTaken_d * 1000, 95) by bin(TimeGenerated, 1m) | order by TimeGenerated asc"
  metric_charts = [
    {
      x     = 0
      y     = 0
      title = " (Replicas): мінімум і максимум за хвилину"
      res   = local.app_id
      ns    = "microsoft.app/containerapps"
      metrics = [
        { name = "Replicas", agg = 2, label = "мінімум" },
        { name = "Replicas", agg = 3, label = "максимум" },
      ]
    },
    {
      x     = 6
      y     = 0
      title = " CPU, % (85 %)"
      res   = local.app_id
      ns    = "microsoft.app/containerapps"
      metrics = [
        { name = "CpuPercentage", agg = 4, label = "середнє CPU, %" },
      ]
    },
    {
      x     = 0
      y     = 4
      title = "Запити за хвилину"
      res   = local.app_id
      ns    = "microsoft.app/containerapps"
      metrics = [
        { name = "Requests", agg = 1, label = "запити" },
      ]
    },
    {
      x     = 0
      y     = 8
      title = "Відповіді 5xx (Gateway, Failed Requests)"
      res   = local.agw_id
      ns    = "microsoft.network/applicationgateways"
      metrics = [
        { name = "FailedRequests", agg = 1, label = "5xx" },
      ]
    },
  ]
}

resource "azurerm_portal_dashboard" "main" {
  name                = "${var.project}-dashboard"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = merge(
          {
            for i, c in local.metric_charts : tostring(i) => {
              position = { x = c.x, y = c.y, colSpan = 6, rowSpan = 4 }
              metadata = {
                type = "Extension/HubsExtension/PartType/MonitorChartPart"
                inputs = [
                  { name = "options", isOptional = true },
                  { name = "sharedTimeRange", isOptional = true }
                ]
                settings = {
                  content = {
                    options = {
                      chart = {
                        title = c.title
                        metrics = [for m in c.metrics : {
                          resourceMetadata    = { id = c.res }
                          name                = m.name
                          namespace           = c.ns
                          aggregationType     = m.agg
                          metricVisualization = { displayName = m.label }
                        }]
                        visualization = { chartType = 2 }
                      }
                    }}}}}},
          {
            "4" = {
              position = { x = 6, y = 4, colSpan = 6, rowSpan = 4 }
              metadata = {
                type = "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart"
                inputs = [
                  { name = "Scope", value = { resourceIds = [azurerm_log_analytics_workspace.logs.id] }, isOptional = true },
                  { name = "Query", value = local.p95_query, isOptional = true },
                  { name = "ControlType", value = "FrameControlChart", isOptional = true },
                  { name = "SpecificChart", value = "Line", isOptional = true },
                  { name = "PartTitle", value = "Латентність p95, мс (журнал Gateway)", isOptional = true },
                  { name = "PartSubTitle", value = azurerm_log_analytics_workspace.logs.name, isOptional = true },
                  {
                    name = "Dimensions"
                    value = {
                      xAxis       = { name = "TimeGenerated", type = "datetime" }
                      yAxis       = [{ name = "p95_ms", type = "real" }]
                      splitBy     = []
                      aggregation = "Sum"
                    }
                    isOptional = true
                  },
                  { name = "LegendOptions", value = { isEnabled = true, position = "Bottom" }, isOptional = true },
                  { name = "IsQueryContainTimeRange", value = false, isOptional = true },
                ]
                settings = {}
              }}})}}
    metadata = { model = {} }
  })
}
