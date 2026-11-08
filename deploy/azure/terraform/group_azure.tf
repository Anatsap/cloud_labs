resource "azurerm_monitor_diagnostic_setting" "agw" {
  name                       = "agw-logs"
  target_resource_id         = azurerm_application_gateway.agw.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }
}
locals {
  app = azurerm_container_app.app.id
  ns  = "microsoft.app/containerapps"

  metric_charts = [
    {
      title = "Екземпляри (Replicas, min/max)"
      metrics = [
        { name = "Replicas", agg = 2, label = "min" },
        { name = "Replicas", agg = 3, label = "max" },
      ]
      filter = null
    },
    {
      title   = "CPU, nanocores"
      metrics = [{ name = "UsageNanoCores", agg = 4, label = "avg CPU" }]
      filter  = null
    },
    {
      title   = "Запити за хвилину"
      metrics = [{ name = "Requests", agg = 1, label = "requests" }]
      filter  = null
    },
    {
      title   = "Відповіді 5xx"
      metrics = [{ name = "Requests", agg = 1, label = "5xx" }]
      filter  = "5xx"
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
              position = { x = (i % 2) * 6, y = floor(i / 2) * 4, colSpan = 6, rowSpan = 4 }
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
                        metrics = [for m in c.metrics : merge(
                          {
                            resourceMetadata    = { id = local.app }
                            name                = m.name
                            namespace           = local.ns
                            aggregationType     = m.agg
                            metricVisualization = { displayName = m.label }
                          },
                          c.filter == null ? {} : {
                            filterCollection = {
                              filters = [{ key = "statusCodeCategory", operator = 0, values = [c.filter] }]
                            }
                          }
                        )]
                        visualization = { chartType = 2 }
                      }
                    }
                  }
                }
              }
            }
          },
          {
            "4" = {
              position = { x = 0, y = 8, colSpan = 12, rowSpan = 4 }
              metadata = {
                type = "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart"
                inputs = [
                  { name = "Scope", value = { resourceIds = [azurerm_log_analytics_workspace.logs.id] } },
                  { name = "Query", value = "AzureDiagnostics | where Category == 'ApplicationGatewayAccessLog' | summarize p95_ms = percentile(timeTaken_d * 1000, 95) by bin(TimeGenerated, 1m) | render timechart" },
                  { name = "PartTitle", value = "Латентність p95, мс" },
                  { name = "PartSubTitle", value = "gateway access log" }
                ]
              }
            }
          }
        )
      }
    }
    metadata = { model = {} }
  })
}