locals {
  ssl_alert_project_id = var.ssl_alert.project_id != null ? var.ssl_alert.project_id : var.project_id

  ssl_alert_notification_channels = var.ssl_alert.notification_enabled ? (length(var.ssl_alert.notification_channels) > 0 ? var.ssl_alert.notification_channels : var.notification_channels) : []
}

resource "google_monitoring_alert_policy" "ssl_expiring_days" {
  for_each = var.ssl_alert.enabled ? toset([for days in var.ssl_alert.threshold_days : tostring(days)]) : []

  display_name = "SSL certificate expiring soon (${each.value} days)"
  combiner     = "OR"
  conditions {
    condition_threshold {
      filter          = <<-EOT
        metric.type="monitoring.googleapis.com/uptime_check/time_until_ssl_cert_expires"
        AND resource.type="uptime_url"
      EOT
      comparison      = "COMPARISON_LT"
      threshold_value = each.value
      duration        = "600s"
      trigger {
        count = 1
      }
      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = [
          "resource.label.*"
        ]
      }
    }
    display_name = "SSL certificate expiring soon (${each.value} days)"
  }

  user_labels = var.ssl_alert.user_labels

  notification_channels = local.ssl_alert_notification_channels
  project               = local.ssl_alert_project_id
}
