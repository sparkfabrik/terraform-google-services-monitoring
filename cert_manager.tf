locals {
  cert_manager_project_id = var.cert_manager.project_id != null ? var.cert_manager.project_id : var.project_id
  cert_manager_alert_documentation = (
    var.cert_manager.alert_documentation != null
    ? var.cert_manager.alert_documentation
    : <<-EOT
      cert-manager is reporting that an Issuer or ClusterIssuer resource referenced by a Certificate cannot be found. This may indicate that the Issuer/ClusterIssuer has been deleted or is otherwise unavailable.
    EOT
  )
  cert_manager_notification_channels = var.cert_manager.notification_enabled ? (length(var.cert_manager.notification_channels) > 0 ? var.cert_manager.notification_channels : var.notification_channels) : []

  cert_manager_log_filter = var.cert_manager.cluster_name != null ? (<<-EOT
    (
      (
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.cert_manager_project_id}"
        AND resource.labels.cluster_name="${var.cert_manager.cluster_name}"
        AND resource.labels.namespace_name="${var.cert_manager.namespace}"
      )
      OR (
        log_id("events")
        AND resource.labels.project_id="${local.cert_manager_project_id}"
        AND resource.labels.cluster_name="${var.cert_manager.cluster_name}"
        AND (
          jsonPayload.involvedObject.namespace="${var.cert_manager.namespace}"
          OR jsonPayload.metadata.namespace="${var.cert_manager.namespace}"
        )
      )
    )
    AND (
      textPayload=~"Referenced \"(Issuer|ClusterIssuer)\" not found"
      OR jsonPayload.message=~"Referenced \"(Issuer|ClusterIssuer)\" not found"
      OR jsonPayload.note=~"Referenced \"(Issuer|ClusterIssuer)\" not found"
    )
    ${trimspace(var.cert_manager.filter_extra)}
  EOT
  ) : ""
}

resource "google_monitoring_alert_policy" "cert_manager_logmatch_alert" {
  count = (
    var.cert_manager.enabled
    && try(var.cert_manager.cluster_name, "") != ""
    && var.cert_manager.cluster_name != null
  ) ? 1 : 0

  display_name = "cert-manager missing Issuer/ClusterIssuer (cluster=${var.cert_manager.cluster_name}, namespace=${var.cert_manager.namespace})"
  combiner     = "OR"
  enabled      = var.cert_manager.enabled

  conditions {
    display_name = "Log match: cert-manager Issuer/ClusterIssuer not found"
    condition_matched_log {
      filter = local.cert_manager_log_filter
    }
  }

  documentation {
    content   = local.cert_manager_alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.cert_manager_notification_channels

  alert_strategy {
    auto_close = "${var.cert_manager.auto_close_seconds}s"
    notification_rate_limit {
      period = var.cert_manager.logmatch_notification_rate_limit
    }
  }
}
