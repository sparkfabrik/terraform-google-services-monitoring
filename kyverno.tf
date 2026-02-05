locals {
  kyverno_project_id            = var.kyverno.project_id != null ? var.kyverno.project_id : var.project_id
  alert_documentation           = var.kyverno.alert_documentation != null ? var.kyverno.alert_documentation : "Kyverno controllers produced ERROR logs in namespace ${var.kyverno.namespace}."
  kyverno_notification_channels = var.kyverno.notification_enabled ? (length(var.kyverno.notification_channels) > 0 ? var.kyverno.notification_channels : var.notification_channels) : []

  kyverno_cluster_name = var.kyverno.cluster_name != null ? trimspace(var.kyverno.cluster_name) : ""

  # Default error patterns for Kyverno log matching
  kyverno_default_error_patterns = [
    "internal error",
    "failed calling webhook",
    "timeout",
    "client-side throttling",
    "failed to run warmup",
    "schema not found",
    "failed to list resources",
    "failed to watch resource",
    "context deadline exceeded",
    "is forbidden",
    "cannot list resource",
    "cannot watch resource",
    "RBAC.*denied",
    "failed to start watcher",
    "leader election lost",
    "unable to update .*WebhookConfiguration",
    "failed to sync",
    "dropping request",
    "failed to load certificate",
    "failed to update lock",
    "the object has been modified",
    "no matches for kind",
    "the server could not find the requested resource",
    "Too Many Requests",
    "x509",
    "is invalid:",
    "connection refused",
    "no agent available",
    "fatal error",
    "panic",
  ]

  # Combine default patterns with included patterns, then filter out excluded ones
  kyverno_all_error_patterns = distinct(concat(
    local.kyverno_default_error_patterns,
    var.kyverno.error_patterns_include
  ))

  kyverno_active_error_patterns = [
    for pattern in local.kyverno_all_error_patterns :
    pattern if !contains(var.kyverno.error_patterns_exclude, pattern)
  ]

  # Build the error patterns filter string
  kyverno_error_patterns_filter = length(local.kyverno_active_error_patterns) > 0 ? join("\n      OR ", [
    for pattern in local.kyverno_active_error_patterns :
    "jsonPayload.error=~\"(?i)${pattern}\""
  ]) : ""

  # Build NOT conditions for excluded patterns on jsonPayload.message
  kyverno_message_exclusions = length(var.kyverno.error_patterns_exclude) > 0 ? join("\n    ", [
    for pattern in var.kyverno.error_patterns_exclude :
    "AND NOT jsonPayload.message=~\"(?i)${pattern}\""
  ]) : ""

  kyverno_log_filter = local.kyverno_cluster_name != "" && length(local.kyverno_active_error_patterns) > 0 ? (<<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.kyverno_project_id}"
    AND resource.labels.cluster_name="${local.kyverno_cluster_name}"
    AND resource.labels.namespace_name="${var.kyverno.namespace}"
    AND (
      labels."k8s-pod/app_kubernetes_io/component"=~"(admission-controller|background-controller|cleanup-controller|reports-controller)"
      OR resource.labels.pod_name=~"kyverno-(admission|background|cleanup|reports)-controller-.*"
    )
    AND (
      ${local.kyverno_error_patterns_filter}
    )
    ${local.kyverno_message_exclusions}
  EOT
  ) : ""
}

resource "google_monitoring_alert_policy" "kyverno_logmatch_alert" {
  count = (
    var.kyverno.enabled
    && local.kyverno_cluster_name != ""
    && length(local.kyverno_active_error_patterns) > 0
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
