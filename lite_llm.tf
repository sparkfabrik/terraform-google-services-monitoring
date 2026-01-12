locals {
  litellm_project = var.litellm.project_id != null ? var.litellm.project_id : var.project_id

  litellm_notification_channels = var.litellm.notification_enabled ? (length(var.litellm.notification_channels) > 0 ? var.litellm.notification_channels : var.notification_channels) : []

  litellm_uptime_checks = var.litellm.enabled ? {
    for app_name, config in var.litellm.apps :
    app_name => config.uptime_check
    if config.uptime_check != null && try(config.uptime_check.enabled, false)
  } : {}

  litellm_container_checks = var.litellm.enabled ? {
    for app_name, config in var.litellm.apps :
    app_name => config.container_check
    if config.container_check != null && try(config.container_check.enabled, false)
  } : {}
}

module "litellm_uptime_checks" {
  for_each = local.litellm_uptime_checks

  source                      = "github.com/sparkfabrik/terraform-sparkfabrik-gcp-http-monitoring?ref=1.0.0"
  gcp_project                 = local.litellm_project
  uptime_monitoring_host      = each.value.host
  uptime_monitoring_path      = each.value.path
  alert_notification_channels = local.litellm_notification_channels
  alert_threshold_value       = 1
  uptime_check_period         = "900s"
}

# Alert: GKE Pod Restarts
# This alert monitors the restart count of LiteLLM containers in GKE.
# It triggers when the delta of restarts is greater than the threshold
# within the specified alignment period.
resource "google_monitoring_alert_policy" "litellm_pod_restart" {
  for_each = local.litellm_container_checks

  project      = local.litellm_project
  display_name = "LiteLLM Pod Restarts (cluster=${var.litellm.cluster_name}, namespace=${each.value.namespace}, app=${each.key})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "LiteLLM container restart count > ${each.value.pod_restart.threshold}"

    condition_threshold {
      filter = <<-EOT
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.litellm_project}"
        AND resource.labels.cluster_name="${var.litellm.cluster_name}"
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
          "metadata.user_labels.\"app.kubernetes.io/instance\"",
        ]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.litellm_notification_channels

  alert_strategy {
    auto_close           = "${each.value.pod_restart.auto_close_seconds}s"
    notification_prompts = each.value.pod_restart.notification_prompts
  }
}
