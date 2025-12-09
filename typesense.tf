
locals {
  typesense_project = var.typesense.project_id != null ? var.typesense.project_id : var.project_id

  typesense_notification_channels = var.typesense.notification_enabled ? (length(var.typesense.notification_channels) > 0 ? var.typesense.notification_channels : var.notification_channels) : []

  typesense_container_checks_enabled = var.typesense.enabled && var.typesense.container_checks != null
}

module "typesense_uptime_checks" {
  for_each = var.typesense.enabled ? var.typesense.uptime_checks_hosts : {}

  source                      = "github.com/sparkfabrik/terraform-sparkfabrik-gcp-http-monitoring?ref=1.0.0"
  gcp_project                 = local.typesense_project
  uptime_monitoring_host      = each.value.host
  uptime_monitoring_path      = length(trimspace(each.value.path)) > 0 ? each.value.path : null
  alert_notification_channels = local.typesense_notification_channels
  alert_threshold_value       = 1
  uptime_check_period         = "900s"
}

# Alert: GKE Pod Restarts
# This alert monitors the restart count of Typesense containers in GKE.
# It triggers when the delta of restarts is greater than the threshold
# within the specified alignment period.
resource "google_monitoring_alert_policy" "typesense_pod_restart" {
  count = var.typesense.enabled && var.typesense.container_checks != null ? 1 : 0

  project      = local.typesense_project
  display_name = "Typesense Pod Restarts (cluster=${var.typesense.container_checks.cluster_name}, namespace=${var.typesense.container_checks.namespace})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Typesense container restart count > ${var.typesense.container_checks.pod_restart.threshold}"

    condition_threshold {
      filter = <<-EOT
        resource.type = "k8s_container"
        AND resource.labels.project_id = "${local.typesense_project}"
        AND resource.labels.cluster_name = "${var.typesense.container_checks.cluster_name}"
        AND resource.labels.namespace_name = "${var.typesense.container_checks.namespace}"
        AND metadata.user_labels.app = "${var.typesense.container_checks.app_name}"
        AND metric.type = "kubernetes.io/container/restart_count"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = var.typesense.container_checks.pod_restart.threshold
      duration        = var.typesense.container_checks.pod_restart.duration

      aggregations {
        alignment_period     = var.typesense.container_checks.pod_restart.alignment_period
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
    auto_close = "86400s" # 24 hours
  }
}

# Alert: Container OOM Killed
# This alert monitors logs for OOMKilled events in Typesense containers.
# It triggers immediately when an OOM event is detected in the logs.
resource "google_monitoring_alert_policy" "typesense_oom_killed" {
  count = var.typesense.enabled && var.typesense.container_checks != null ? 1 : 0

  project      = local.typesense_project
  display_name = "Typesense OOM Killed (cluster=${var.typesense.container_checks.cluster_name}, namespace=${var.typesense.container_checks.namespace})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Log match: Typesense OOMKilled"

    condition_matched_log {
      filter = <<-EOT
        resource.type="k8s_container"
        resource.labels.project_id="${local.typesense_project}"
        resource.labels.cluster_name="${var.typesense.container_checks.cluster_name}"
        resource.labels.namespace_name="${var.typesense.container_checks.namespace}"
        metadata.user_labels.app = "${var.typesense.container_checks.app_name}"
        (textPayload:"OOMKilled" OR jsonPayload.reason="OOMKilled" OR jsonPayload.message=~"OOMKilled")
      EOT
    }
  }

  notification_channels = local.typesense_notification_channels

  alert_strategy {
    auto_close = "${var.typesense.container_checks.oom_killed.auto_close_seconds}s"
    notification_rate_limit {
      period = var.typesense.container_checks.oom_killed.notification_rate_limit
    }
  }
}

