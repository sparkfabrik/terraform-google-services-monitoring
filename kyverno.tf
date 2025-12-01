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
        "(?i)internal error"
        OR "(?i)failed calling webhook"
        OR "(?i)timeout"
        OR "(?i)client-side throttling"
        OR "(?i)failed to run warmup"
        OR "(?i)schema not found"
        OR "(?i)list resources failed"
        OR "(?i)failed to watch resource"
        OR "(?i)context deadline exceeded"
        OR "(?i)i/o timeout"
        OR "(?i)is forbidden"
        OR "(?i)cannot list resource"
        OR "(?i)cannot watch resource"
        OR "(?i)RBAC.*denied"
        OR "(?i)failed to start watcher"
        OR "(?i)failed to acquire lease"
        OR "(?i)leader election lost"
        OR "(?i)unable to update .*WebhookConfiguration"
        OR "(?i)failed to sync"
        OR "(?i)dropping request"
        OR "(?i)failed to load certificate"
        OR "(?i)failed to update lock"
        OR "(?i)the object has been modified"
        OR "(?i)no matches for kind"
        OR "(?i)the server could not find the requested resource"
        OR "(?i)Too Many Requests"
        OR "(?i)x509"
        OR "(?i)is invalid:"
        OR "(?i)connection refused"
        OR "(?i)fatal error"
        OR "(?i)panic"
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
