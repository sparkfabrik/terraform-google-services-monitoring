locals {
  typesense_project = var.typesense.project_id != null ? var.typesense.project_id : var.project_id

  typesense_notification_channels = var.typesense.notification_enabled ? (length(var.typesense.notification_channels) > 0 ? var.typesense.notification_channels : var.notification_channels) : []

  typesense_uptime_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config.uptime_check
    if config.uptime_check != null && try(config.uptime_check.enabled, false)
  } : {}

  typesense_container_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config.container_check
    if config.container_check != null && try(config.container_check.enabled, false)
  } : {}

  typesense_log_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config.log_check
    if config.log_check != null && try(config.log_check.enabled, false)
  } : {}

  typesense_flood_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config.flood_check
    if config.flood_check != null && try(config.flood_check.enabled, false)
  } : {}
}

module "typesense_uptime_checks" {
  for_each = local.typesense_uptime_checks

  source                      = "./modules/http_monitoring"
  gcp_project_id              = local.typesense_project
  uptime_monitoring_host      = each.value.host
  uptime_monitoring_path      = each.value.path
  alert_notification_channels = local.typesense_notification_channels
  alert_threshold_value       = 1
  uptime_check_period         = "900s"
}

# Alert: GKE Pod Restarts
# This alert monitors the restart count of Typesense containers in GKE.
# It triggers when the delta of restarts is greater than the threshold
# within the specified alignment period.
resource "google_monitoring_alert_policy" "typesense_pod_restart" {
  for_each = local.typesense_container_checks

  project      = local.typesense_project
  display_name = "Typesense Pod Restarts (cluster=${var.typesense.cluster_name}, namespace=${each.value.namespace}, app=${each.key})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Typesense container restart count > ${each.value.pod_restart.threshold}"

    condition_threshold {
      filter = <<-EOT
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.typesense_project}"
        AND resource.labels.cluster_name="${var.typesense.cluster_name}"
        AND resource.labels.namespace_name="${each.value.namespace}"
        AND metric.type="kubernetes.io/container/restart_count"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.pod_restart.threshold
      duration        = "${each.value.pod_restart.duration}s"

      aggregations {
        alignment_period     = "${each.value.pod_restart.alignment_period}s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "metadata.user_labels.app",
        ]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.typesense_notification_channels

  alert_strategy {
    auto_close           = "${each.value.pod_restart.auto_close_seconds}s"
    notification_prompts = each.value.pod_restart.notification_prompts
  }
}

# Alert: Typesense Log Errors
# This alert monitors Cloud Logging for Typesense container logs at or above
# a configurable severity threshold. It fires on the first matching log entry,
# with notification rate limiting to prevent alert fatigue.
resource "google_monitoring_alert_policy" "typesense_logmatch_alert" {
  for_each = local.typesense_log_checks

  project      = local.typesense_project
  display_name = "Typesense ERROR logs (cluster=${var.typesense.cluster_name}, namespace=${each.value.namespace}, app=${each.key})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Typesense log severity >= ${each.value.min_severity}"
    condition_matched_log {
      filter = <<-EOT
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.typesense_project}"
        AND resource.labels.cluster_name="${var.typesense.cluster_name}"
        AND resource.labels.namespace_name="${each.value.namespace}"
        AND resource.labels.container_name="typesense"
        AND severity>="${each.value.min_severity}"
      EOT
    }
  }

  notification_channels = local.typesense_notification_channels

  alert_strategy {
    auto_close = "${each.value.auto_close_seconds}s"
    notification_rate_limit {
      period = each.value.logmatch_notification_rate_limit
    }
  }
}

# Metric: Typesense Log Volume
# User-defined log-based counter metric counting all log entries from the
# Typesense container in a given namespace. Used by the flood alert below.
resource "google_logging_metric" "typesense_log_flood" {
  for_each = local.typesense_flood_checks

  project = local.typesense_project
  name    = "typesense_log_volume_${each.key}"

  filter = <<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.typesense_project}"
    AND resource.labels.cluster_name="${var.typesense.cluster_name}"
    AND resource.labels.namespace_name="${each.value.namespace}"
    AND resource.labels.container_name="typesense"
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Typesense log entry count (cluster=${var.typesense.cluster_name}, namespace=${each.value.namespace}, app=${each.key})"
  }
}

# Alert: Typesense Log Flood
# Fires when the Typesense container log entry rate (entries/minute) exceeds
# the configured threshold over the configured duration. Designed to catch
# Raft consensus storms and similar log-flooding failure modes before they
# impact billing.
resource "google_monitoring_alert_policy" "typesense_flood_alert" {
  for_each = local.typesense_flood_checks

  project      = local.typesense_project
  display_name = "Typesense log flood (cluster=${var.typesense.cluster_name}, namespace=${each.value.namespace}, app=${each.key})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Typesense log rate > ${each.value.threshold_entries_per_minute} entries/min"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.typesense_log_flood[each.key].name}\" AND resource.type=\"global\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold_entries_per_minute
      duration        = "${each.value.duration_seconds}s"

      aggregations {
        alignment_period   = "${each.value.alignment_period_seconds}s"
        per_series_aligner = "ALIGN_RATE"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.typesense_notification_channels

  alert_strategy {
    auto_close = "${each.value.auto_close_seconds}s"
    notification_rate_limit {
      period = each.value.notification_rate_limit
    }
  }

  depends_on = [google_logging_metric.typesense_log_flood]
}
