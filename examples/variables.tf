
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
  description = "Configuration for Kyverno monitoring: level-1 restart alert, two-tier service-error alerts and a broken-policy engine alert."
  type = object({
    enabled               = optional(bool, true)
    cluster_name          = string
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    alert_documentation   = optional(string, null)
    namespace             = optional(string, "kyverno")

    restart_check = optional(object({
      enabled              = optional(bool, true)
      threshold            = optional(number, 0)
      alignment_period     = optional(number, 60)
      duration             = optional(number, 60)
      auto_close_seconds   = optional(number, 3600)
      notification_prompts = optional(list(string), null)
    }), {})

    service_errors_check = optional(object({
      enabled                 = optional(bool, true)
      threshold               = optional(number, 5)
      alignment_period        = optional(number, 600)
      duration                = optional(number, 0)
      auto_close_seconds      = optional(number, 3600)
      notification_rate_limit = optional(string, "300s")
    }), {})

    volume_check = optional(object({
      enabled                 = optional(bool, true)
      threshold               = optional(number, 10)
      alignment_period        = optional(number, 60)
      duration                = optional(number, 900)
      auto_close_seconds      = optional(number, 3600)
      notification_rate_limit = optional(string, "3600s")
    }), {})

    engine_check = optional(object({
      enabled                 = optional(bool, true)
      threshold               = optional(number, 0)
      alignment_period        = optional(number, 60)
      duration                = optional(number, 300)
      auto_close_seconds      = optional(number, 3600)
      notification_rate_limit = optional(string, "3600s")
    }), {})

    dashboard = optional(object({
      enabled      = optional(bool, true)
      window_hours = optional(number, 25)
    }), {})
  })
}

variable "cert_manager" {
  description = "Configuration for cert-manager missing issuer log alert. Allows customization of project, cluster, namespace, notification channels, alert documentation, enablement, extra filters, auto-close timing, and notification rate limiting."
  type = object({
    enabled                          = optional(bool, true)
    cluster_name                     = string
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
