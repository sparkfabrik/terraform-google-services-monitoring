
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
    cluster_name                     = string
    project_id                       = optional(string, null)
    notification_channels            = optional(list(string), [])
    logmatch_notification_rate_limit = optional(string, "300s")
    alert_documentation              = optional(string, null)
    use_metric_threshold             = optional(bool, false)
    metric_threshold_count           = optional(number, 2)
    metric_lookback_minutes          = optional(number, 1)
    auto_close_seconds               = optional(number, 3600)
    enabled                          = optional(bool, true)
    filter_extra                     = optional(string, "")
    namespace                        = optional(string, "kyverno")
  })
}
