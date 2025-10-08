locals {
  kyverno_project_id            = var.kyverno.project_id != null ? var.kyverno.project_id : var.project_id
  alert_documentation           = var.kyverno.alert_documentation != null ? var.kyverno.alert_documentation : "Kyverno controllers produced ERROR logs in namespace ${var.kyverno.namespace}."
  kyverno_notification_channels = var.kyverno.notification_enabled ? (length(var.kyverno.notification_channels) > 0 ? var.kyverno.notification_channels : var.notification_channels) : []

  kyverno_log_filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.project_id="${local.kyverno_project_id}"
    resource.labels.cluster_name="${var.kyverno.cluster_name}"
    resource.labels.namespace_name="${var.kyverno.namespace}"
    severity>=ERROR
    (
      labels."k8s-pod/app_kubernetes_io/component"=~"(admission-controller|background-controller|cleanup-controller|reports-controller)"
      OR resource.labels.pod_name=~"kyverno-(admission|background|cleanup|reports)-controller-.*"
    )
    ${trimspace(var.kyverno.filter_extra)}
  EOT
}

resource "google_monitoring_alert_policy" "kyverno_logmatch_alert" {
  count = (
    var.kyverno.enabled
    && trimspace(var.kyverno.cluster_name) != ""
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
