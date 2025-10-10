locals {
  certificate_project_id = var.certificate.project_id != null ? var.certificate.project_id : var.project_id
  certificate_alert_documentation = (
    var.certificate.alert_documentation != null
    ? var.certificate.alert_documentation
    : <<-EOT
      cert-manager is reporting that an Issuer or ClusterIssuer resource referenced by a Certificate cannot be found. This may indicate that the Issuer/ClusterIssuer has been deleted or is otherwise unavailable.
    EOT
  )
  certificate_notification_channels = var.certificate.notification_enabled ? (length(var.certificate.notification_channels) > 0 ? var.certificate.notification_channels : var.notification_channels) : []

  certificate_log_filter = <<-EOT
    (
      (
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.certificate_project_id}"
        AND resource.labels.cluster_name="${var.certificate.cluster_name}"
        AND resource.labels.namespace_name="${var.certificate.namespace}"
      )
      OR (
        log_id("events")
        AND resource.labels.project_id="${local.certificate_project_id}"
        AND resource.labels.cluster_name="${var.certificate.cluster_name}"
        AND (
          jsonPayload.involvedObject.namespace="${var.certificate.namespace}"
          OR jsonPayload.metadata.namespace="${var.certificate.namespace}"
        )
      )
    )
    AND (
      textPayload=~"Referenced \\"(Issuer|ClusterIssuer)\\" not found"
      OR jsonPayload.message=~"Referenced \\"(Issuer|ClusterIssuer)\\" not found"
      OR jsonPayload.note=~"Referenced \\"(Issuer|ClusterIssuer)\\" not found"
    )
    ${trimspace(var.certificate.filter_extra)}
  EOT
}

resource "google_monitoring_alert_policy" "certificate_logmatch_alert" {
  count = (
    var.certificate.enabled
    && trimspace(var.certificate.cluster_name) != ""
  ) ? 1 : 0

  display_name = "cert-manager missing Issuer/ClusterIssuer (cluster=${var.certificate.cluster_name}, namespace=${var.certificate.namespace})"
  combiner     = "OR"
  enabled      = var.certificate.enabled

  conditions {
    display_name = "Log match: cert-manager Issuer/ClusterIssuer not found"
    condition_matched_log {
      filter = local.certificate_log_filter
    }
  }

  documentation {
    content   = local.certificate_alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.certificate_notification_channels

  alert_strategy {
    auto_close = "${var.certificate.auto_close_seconds}s"
    notification_rate_limit {
      period = var.certificate.logmatch_notification_rate_limit
    }
  }
}
