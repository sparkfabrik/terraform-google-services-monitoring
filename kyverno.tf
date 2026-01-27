locals {
  kyverno_project_id            = var.kyverno.project_id != null ? var.kyverno.project_id : var.project_id
  alert_documentation           = var.kyverno.alert_documentation != null ? var.kyverno.alert_documentation : "Kyverno controllers produced ERROR logs in namespace ${var.kyverno.namespace}."
  kyverno_notification_channels = var.kyverno.notification_enabled ? (length(var.kyverno.notification_channels) > 0 ? var.kyverno.notification_channels : var.notification_channels) : []

  kyverno_log_filter = var.kyverno.cluster_name != null ? (<<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.kyverno_project_id}"
    AND resource.labels.cluster_name="${var.kyverno.cluster_name}"
    AND resource.labels.namespace_name="${var.kyverno.namespace}"
    AND (
      labels."k8s-pod/app_kubernetes_io/component"=~"(admission-controller|background-controller|cleanup-controller|reports-controller)"
      OR resource.labels.pod_name=~"kyverno-(admission|background|cleanup|reports)-controller-.*"
    )
    AND (
      jsonPayload.error=~"(?i)internal error"
      OR jsonPayload.error=~"(?i)failed calling webhook"
      OR jsonPayload.error=~"(?i)timeout"
      OR jsonPayload.error=~"(?i)client-side throttling"
      OR jsonPayload.error=~"(?i)failed to run warmup"
      OR jsonPayload.error=~"(?i)schema not found"
      OR jsonPayload.error=~"(?i)list resources failed"
      OR jsonPayload.error=~"(?i)failed to watch resource"
      OR jsonPayload.error=~"(?i)context deadline exceeded"
      OR jsonPayload.error=~"(?i)i/o timeout"
      OR jsonPayload.error=~"(?i)is forbidden"
      OR jsonPayload.error=~"(?i)cannot list resource"
      OR jsonPayload.error=~"(?i)cannot watch resource"
      OR jsonPayload.error=~"(?i)RBAC.*denied"
      OR jsonPayload.error=~"(?i)failed to start watcher"
      OR jsonPayload.error=~"(?i)failed to acquire lease"
      OR jsonPayload.error=~"(?i)leader election lost"
      OR jsonPayload.error=~"(?i)unable to update .*WebhookConfiguration"
      OR jsonPayload.error=~"(?i)failed to sync"
      OR jsonPayload.error=~"(?i)dropping request"
      OR jsonPayload.error=~"(?i)failed to load certificate"
      OR jsonPayload.error=~"(?i)failed to update lock"
      OR jsonPayload.error=~"(?i)the object has been modified"
      OR jsonPayload.error=~"(?i)no matches for kind"
      OR jsonPayload.error=~"(?i)the server could not find the requested resource"
      OR jsonPayload.error=~"(?i)Too Many Requests"
      OR jsonPayload.error=~"(?i)x509"
      OR jsonPayload.error=~"(?i)is invalid:"
      OR jsonPayload.error=~"(?i)connection refused"
      OR jsonPayload.error=~"(?i)no agent available"
      OR jsonPayload.error=~"(?i)fatal error"
      OR jsonPayload.error=~"(?i)panic"
    )
    ${trimspace(var.kyverno.filter_extra)}
  EOT
  ) : ""
}

resource "google_monitoring_alert_policy" "kyverno_logmatch_alert" {
  count = (
    var.kyverno.enabled
    && try(var.kyverno.cluster_name, "") != ""
    && var.kyverno.cluster_name != null
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
