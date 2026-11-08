data "azurerm_subscription" "current" {}

resource "azurerm_consumption_budget_subscription" "budget" {
  name            = "${var.project}-budget"
  subscription_id = data.azurerm_subscription.current.id
  amount          = 10
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.budget_email]
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}