
variable "project_id" {
  description = "The Google Cloud project ID where logging exclusions will be created"
  type        = string
}

variable "notification_channels" {
  description = "List of notification channel IDs to notify when an alert is triggered"
  type        = list(string)
  default     = []
}

variable "kyverno" {
  description = "Configuration for Kyverno monitoring alerts. Allows customization of cluster name, project, notification channels, alert documentation, metric thresholds, auto-close timing, enablement, extra filters, and namespace."
  type = object({
    enabled                 = optional(bool, true)
    project_id              = optional(string, null)
    cluster_name            = string
    namespace               = optional(string, "kyverno")
    notification_enabled    = optional(bool, true)
    notification_channels   = optional(list(string), [])
    alert_documentation     = optional(string, null)
    metric_threshold_count  = optional(number, 2)
    metric_lookback_minutes = optional(number, 1)
    auto_close_seconds      = optional(number, 3600)
    filter_extra            = optional(string, "")
  })
}

variable "cert_manager" {
  description = "Configuration for cert-manager missing issuer log alert. Allows customization of project, cluster, namespace, notification channels, alert documentation, enablement, extra filters, auto-close timing, and notification rate limiting."
  type = object({
    enabled                          = optional(bool, true)
    cluster_name                     = optional(string, "")
    project_id                       = optional(string, null)
    namespace                        = optional(string, "cert-manager")
    notification_enabled             = optional(bool, true)
    notification_channels            = optional(list(string), [])
    logmatch_notification_rate_limit = optional(string, "300s")
    alert_documentation              = optional(string, null)
    auto_close_seconds               = optional(number, 3600)
    filter_extra                     = optional(string, "")
  })
}
