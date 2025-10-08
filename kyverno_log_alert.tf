locals {
  kyverno_project_id            = var.kyverno.project_id != null ? var.kyverno.project_id : var.project_id
  alert_documentation           = var.kyverno.alert_documentation != null ? var.kyverno.alert_documentation : "Kyverno controllers produced ERROR logs in namespace ${var.kyverno.namespace}."
  kyverno_notification_channels = var.kyverno.notification_enabled ? (length(var.kyverno.notification_channels) > 0 ? var.kyverno.notification_channels : var.notification_channels) : []

  kyverno_log_filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.project_id="${local.kyverno_project_id}"
    resource.labels.cluster_name="${var.kyverno.cluster_name}"
    resource.labels.namespace_name="${var.kyverno.namespace}"
    severity>=ERROR
    (
      labels."k8s-pod/app_kubernetes_io/component"=~"(admission-controller|background-controller|cleanup-controller|reports-controller)"
      OR resource.labels.pod_name=~"kyverno-(admission|background|cleanup|reports)-controller-.*"
    )
    ${trimspace(var.kyverno.filter_extra)}
  EOT

  kyverno_metric_name = lower(replace(
    "kyverno_error_logs_count_${var.kyverno.cluster_name}_${var.kyverno.namespace}",
    "/[^a-zA-Z0-9_]/", "_"
  ))
}

resource "google_monitoring_alert_policy" "kyverno_logmatch_alert" {
  count = (
    var.kyverno.enabled
    && !var.kyverno.use_metric_threshold
    && trimspace(var.kyverno.cluster_name) != ""
  ) ? 1 : 0

  display_name = "Kyverno controllers ERROR logs (namespace=${var.kyverno.namespace})"
  combiner     = "OR"
  enabled      = var.kyverno.enabled

  conditions {
    display_name = "Kyverno ERROR in logs"
    condition_matched_log {
      filter = local.kyverno_log_filter
    }
  }

  documentation {
    content   = local.alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.kyverno_notification_channels

  alert_strategy {
    auto_close = "${var.kyverno.auto_close_seconds}s"
    notification_rate_limit {
      period = var.kyverno.logmatch_notification_rate_limit
    }
  }
}

resource "google_logging_metric" "kyverno_error_metric" {
  count = (
    var.kyverno.enabled
    && var.kyverno.use_metric_threshold
    && trimspace(var.kyverno.cluster_name) != ""
  ) ? 1 : 0

  name        = local.kyverno_metric_name
  description = "Count of ERROR+ logs from Kyverno controllers in namespace ${var.kyverno.namespace}"
  filter      = local.kyverno_log_filter

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "kyverno_metric_threshold_alert" {
  count = (
    var.kyverno.enabled
    && var.kyverno.use_metric_threshold
    && trimspace(var.kyverno.cluster_name) != ""
  ) ? 1 : 0

  display_name = "Kyverno ERROR rate alert (namespace=${var.kyverno.namespace})"
  combiner     = "OR"
  enabled      = var.kyverno.enabled

  conditions {
    display_name = "Kyverno ERROR rate alert >= ${var.kyverno.metric_threshold_count} logs in ${var.kyverno.metric_lookback_minutes} min (namespace ${var.kyverno.namespace})"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${local.kyverno_metric_name}\" resource.type=\"global\""
      comparison      = "COMPARISON_GE"
      threshold_value = var.kyverno.metric_threshold_count
      duration        = "0s"

      aggregations {
        alignment_period     = "${var.kyverno.metric_lookback_minutes * 60}s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = []
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = local.alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.kyverno_notification_channels

  alert_strategy {
    auto_close = "${var.kyverno.auto_close_seconds}s"
  }
}
