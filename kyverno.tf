locals {
  kyverno_project_id            = var.kyverno.project_id != null ? var.kyverno.project_id : var.project_id
  alert_documentation           = var.kyverno.alert_documentation != null ? var.kyverno.alert_documentation : "Kyverno controllers produced ERROR logs in namespace ${var.kyverno.namespace}."
  kyverno_notification_channels = var.kyverno.notification_enabled ? (length(var.kyverno.notification_channels) > 0 ? var.kyverno.notification_channels : var.notification_channels) : []

  kyverno_cluster_name = var.kyverno.cluster_name != null ? trimspace(var.kyverno.cluster_name) : ""

  # Default message patterns for Kyverno log matching (matches against jsonPayload.message)
  kyverno_default_message_patterns = [
    "failed to list resources",
    "failed to watch resource",
    "failed to start watcher",
    "failed to sync",
    "failed to run warmup",
    "failed to load certificate",
    "failed to update lock",
    "failed to update lease",
    "failed to process request",
    "failed to check permissions",
    "failed to scan resource",
    "failed to fetch data",
    "failed to substitute variables",
    "failed calling webhook",
    "leader election lost",
    "dropping request",
    "panic",
  ]

  # Combine default patterns with included patterns, then filter out excluded ones
  kyverno_all_message_patterns = distinct(concat(
    local.kyverno_default_message_patterns,
    var.kyverno.error_patterns_include
  ))

  kyverno_active_message_patterns = [
    for pattern in local.kyverno_all_message_patterns :
    pattern if !contains(var.kyverno.error_patterns_exclude, pattern)
  ]

  # Build the message patterns filter string
  kyverno_message_patterns_filter = length(local.kyverno_active_message_patterns) > 0 ? join("\n      OR ", [
    for pattern in local.kyverno_active_message_patterns :
    "jsonPayload.message=~\"(?i)${pattern}\""
  ]) : ""

  kyverno_log_filter = local.kyverno_cluster_name != "" && length(local.kyverno_active_message_patterns) > 0 ? (<<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.kyverno_project_id}"
    AND resource.labels.cluster_name="${local.kyverno_cluster_name}"
    AND resource.labels.namespace_name="${var.kyverno.namespace}"
    AND severity=ERROR
    AND (
      labels."k8s-pod/app_kubernetes_io/component"=~"(admission-controller|background-controller|cleanup-controller|reports-controller)"
      OR resource.labels.pod_name=~"kyverno-(admission|background|cleanup|reports)-controller-.*"
    )
    AND (
      ${local.kyverno_message_patterns_filter}
    )
  EOT
  ) : ""
}

resource "google_monitoring_alert_policy" "kyverno_logmatch_alert" {
  count = (
    var.kyverno.enabled
    && local.kyverno_cluster_name != ""
    && length(local.kyverno_active_message_patterns) > 0
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
