variable "project_id" {
  description = "The Google Cloud project ID where logging exclusions will be created"
  type        = string
}

variable "notification_channels" {
  description = "List of notification channel IDs to notify when an alert is triggered"
  type        = list(string)
  default     = []
}

variable "cloud_sql" {
  description = "Configuration for Cloud SQL monitoring alerts. Supports customization of project, auto-close timing, notification channels, and per-instance alert thresholds for CPU, memory, and disk utilization."
  type = object({
    project_id            = optional(string, null)
    auto_close            = optional(string, "86400s") # default 24h
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    instances = optional(map(object({
      cpu_utilization = optional(list(object({
        severity         = optional(string, "WARNING"),
        threshold        = optional(number, 0.90)
        alignment_period = optional(string, "120s")
        duration         = optional(string, "300s")
        })), [
        {
          threshold = 0.85,
          duration  = "1200s",
        },
        {
          severity         = "CRITICAL",
          threshold        = 1,
          duration         = "300s",
          alignment_period = "60s",
        }
      ])
      memory_utilization = optional(list(object({
        severity         = optional(string, "WARNING"),
        threshold        = optional(number, 0.90)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "300s")
        })), [
        {
          severity = "WARNING",
        },
        {
          severity  = "CRITICAL",
          threshold = 0.95,
        }
      ])
      disk_utilization = optional(list(object({
        severity         = optional(string, "WARNING"),
        threshold        = optional(number, 0.85)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "600s")
        })), [
        {
          severity = "WARNING",
        },
        {
          severity  = "CRITICAL",
          threshold = 0.95,
        }
      ])
    })), {})
  })
}

variable "kyverno" {
  description = "Configuration for Kyverno monitoring alerts. Allows customization of cluster name, project, notification channels, alert documentation, metric thresholds, auto-close timing, enablement, extra filters, and namespace."
  type = object({
    enabled               = optional(bool, true)
    cluster_name          = string
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    # Rate limit for notifications, e.g. "300s" for 5 minutes, used only for log match alerts
    logmatch_notification_rate_limit = optional(string, "300s")
    alert_documentation              = optional(string, null)
    auto_close_seconds               = optional(number, 3600)
    filter_extra                     = optional(string, "")
    namespace                        = optional(string, "kyverno")
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

variable "typesense" {
  description = "Configuration for Typesense monitoring alerts. Supports uptime checks for HTTP endpoints and container-level alerts (pod restarts, OOM) in GKE. For container checks, 'app_name' refers to the Kubernetes 'app' label on the containers."
  default = {}

  type = object({
    enabled               = optional(bool, false)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])

    # Uptime checks configuration
    uptime_checks_hosts = optional(map(object({
      host = string
      path = optional(string, "/readyz")
    })), {})

    # Container checks configuration (GKE)
    container_checks = optional(object({
      cluster_name = string
      namespace    = string
      app_name     = string
      pod_restart = optional(object({
        threshold        = optional(number, 1)
        alignment_period = optional(string, "180s")
        duration         = optional(string, "0s")
      }), {})
      oom_killed = optional(object({
        notification_rate_limit = optional(string, "180s")
        auto_close_seconds      = optional(number, 300)
      }), {})
    }), null)
  })

  validation {
    condition = (
      var.typesense.container_checks == null ? true :
      (
        try(var.typesense.container_checks.app_name, null) != null &&
        try(trimspace(var.typesense.container_checks.app_name), "") != "" &&
        try(var.typesense.container_checks.cluster_name, null) != null &&
        try(trimspace(var.typesense.container_checks.cluster_name), "") != "" &&
        try(var.typesense.container_checks.namespace, null) != null &&
        try(trimspace(var.typesense.container_checks.namespace), "") != ""
      )
    )
    error_message = "When container_checks is provided, 'cluster_name', 'app_name', and 'namespace' must all be non-empty strings."
  }
}
