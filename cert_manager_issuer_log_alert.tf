locals {
  cert_manager_issuer_project_id = var.cert_manager_issuer.project_id != null ? var.cert_manager_issuer.project_id : var.project_id
  cert_manager_issuer_alert_documentation = (
    var.cert_manager_issuer.alert_documentation != null
    ? var.cert_manager_issuer.alert_documentation
    : <<-EOT
      cert-manager is reporting that an Issuer or ClusterIssuer resource referenced by a cert_manager_issuer cannot be found. This may indicate that the Issuer/ClusterIssuer has been deleted or is otherwise unavailable.
    EOT
  )
  cert_manager_issuer_notification_channels = var.cert_manager_issuer.notification_enabled ? (length(var.cert_manager_issuer.notification_channels) > 0 ? var.cert_manager_issuer.notification_channels : var.notification_channels) : []

  cert_manager_issuer_log_filter = <<-EOT
    (
      (
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.cert_manager_issuer_project_id}"
        AND resource.labels.cluster_name="${var.cert_manager_issuer.cluster_name}"
        AND resource.labels.namespace_name="${var.cert_manager_issuer.namespace}"
      )
      OR (
        log_id("events")
        AND resource.labels.project_id="${local.cert_manager_issuer_project_id}"
        AND resource.labels.cluster_name="${var.cert_manager_issuer.cluster_name}"
        AND (
          jsonPayload.involvedObject.namespace="${var.cert_manager_issuer.namespace}"
          OR jsonPayload.metadata.namespace="${var.cert_manager_issuer.namespace}"
        )
      )
    )
    AND (
      textPayload=~"Referenced \"(Issuer|ClusterIssuer)\" not found"
      OR jsonPayload.message=~"Referenced \"(Issuer|ClusterIssuer)\" not found"
      OR jsonPayload.note=~"Referenced \"(Issuer|ClusterIssuer)\" not found"
    )
    ${trimspace(var.cert_manager_issuer.filter_extra)}
  EOT
}

resource "google_monitoring_alert_policy" "cert_manager_issuer_logmatch_alert" {
  count = (
    var.cert_manager_issuer.enabled
    && trimspace(var.cert_manager_issuer.cluster_name) != ""
  ) ? 1 : 0

  display_name = "cert-manager missing Issuer/ClusterIssuer (cluster=${var.cert_manager_issuer.cluster_name}, namespace=${var.cert_manager_issuer.namespace})"
  combiner     = "OR"
  enabled      = var.cert_manager_issuer.enabled

  conditions {
    display_name = "Log match: cert-manager Issuer/ClusterIssuer not found"
    condition_matched_log {
      filter = local.cert_manager_issuer_log_filter
    }
  }

  documentation {
    content   = local.cert_manager_issuer_alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.cert_manager_issuer_notification_channels

  alert_strategy {
    auto_close = "${var.cert_manager_issuer.auto_close_seconds}s"
    notification_rate_limit {
      period = var.cert_manager_issuer.logmatch_notification_rate_limit
    }
  }
}
