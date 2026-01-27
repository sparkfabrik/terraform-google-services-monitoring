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
