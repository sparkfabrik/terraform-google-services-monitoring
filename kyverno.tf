locals {
  kyverno_project_id            = var.kyverno.project_id != null ? var.kyverno.project_id : var.project_id
  alert_documentation           = var.kyverno.alert_documentation != null ? var.kyverno.alert_documentation : "Kyverno controllers produced ERROR logs in namespace ${var.kyverno.namespace}."
  kyverno_notification_channels = var.kyverno.notification_enabled ? (length(var.kyverno.notification_channels) > 0 ? var.kyverno.notification_channels : var.notification_channels) : []

  kyverno_log_filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.project_id="${local.kyverno_project_id}"
    resource.labels.cluster_name="${var.kyverno.cluster_name}"
    resource.labels.namespace_name="${var.kyverno.namespace}"
    (
      labels."k8s-pod/app_kubernetes_io/component"=~"(admission-controller|background-controller|cleanup-controller|reports-controller)"
      OR
      resource.labels.pod_name=~"kyverno-(admission|background|cleanup|reports)-controller-.*"
    )
    textPayload=~(
        "internal error"
        OR "failed calling webhook"
        OR "timeout"
        OR "client-side throttling"
        OR "failed to run warmup"
        OR "schema not found"
        OR "list resources failed"
        OR "failed to watch resource"
        OR "context deadline exceeded"
        OR "i/o timeout"
        OR "is forbidden"
        OR "cannot list resource"
        OR "cannot watch resource"
        OR "RBAC.*denied"
        OR "failed to start watcher"
        OR "failed to acquire lease"
        OR "leader election lost"
        OR "unable to update .*WebhookConfiguration"
        OR "failed to sync"
        OR "dropping request"
        OR "failed to load certificate"
        OR "Failed to update lock"
        OR "the object has been modified"
        OR "no matches for kind"
        OR "the server could not find the requested resource"
        OR "Too Many Requests"
        OR "x509"
        OR "is invalid:"
        OR "connection refused"
        OR "fatal error"
        OR "panic"
    )
    ${trimspace(var.kyverno.filter_extra)}
  EOT
}

resource "google_monitoring_alert_policy" "kyverno_logmatch_alert" {
  count = (
    var.kyverno.enabled
    && trimspace(var.kyverno.cluster_name) != ""
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
