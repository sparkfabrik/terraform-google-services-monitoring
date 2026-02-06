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
  default     = {}
  type = object({
    enabled               = optional(bool, true)
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
  description = "Configuration for Kyverno monitoring alerts. Allows customization of cluster name, project, notification channels, alert documentation, metric thresholds, auto-close timing, enablement, message pattern inclusions/exclusions for jsonPayload.message matching, and namespace."
  default     = {}
  type = object({
    enabled               = optional(bool, true)
    cluster_name          = optional(string, null)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    # Rate limit for notifications, e.g. "300s" for 5 minutes, used only for log match alerts
    logmatch_notification_rate_limit = optional(string, "300s")
    alert_documentation              = optional(string, null)
    auto_close_seconds               = optional(number, 3600)
    namespace                        = optional(string, "kyverno")
    # List of message patterns to exclude from the default set (matches against jsonPayload.message).
    # Default patterns available for exclusion:
    #   "failed to list resources", "failed to watch resource", "failed to start watcher",
    #   "failed to sync", "failed to run warmup", "failed to load certificate",
    #   "failed to update lock", "failed to process request", "failed to check permissions",
    #   "failed to scan resource", "failed to fetch data", "failed to substitute variables",
    #   "failed calling webhook", "leader election lost", "dropping request", "panic"
    error_patterns_exclude = optional(list(string), [])
    # List of additional regex message patterns to include (added to default set)
    # e.g. ["failed to authenticate.", "failed to connect."]
    error_patterns_include = optional(list(string), [])
  })

  validation {
    condition = (
      !var.kyverno.enabled ||
      (var.kyverno.cluster_name != null && var.kyverno.cluster_name != "")
    )
    error_message = "When 'enabled' is true, 'cluster_name' must be provided and cannot be empty."
  }

  validation {
    condition = alltrue([
      for pattern in var.kyverno.error_patterns_exclude : contains([
        "failed to list resources",
        "failed to watch resource",
        "failed to start watcher",
        "failed to sync",
        "failed to run warmup",
        "failed to load certificate",
        "failed to update lock",
        "failed to process request",
        "failed to check permissions",
        "failed to scan resource",
        "failed to fetch data",
        "failed to substitute variables",
        "failed calling webhook",
        "leader election lost",
        "dropping request",
        "panic",
      ], pattern)
    ])
    error_message = "error_patterns_exclude contains invalid pattern(s). Only default patterns can be excluded. Check the variable description for the list of valid patterns."
  }

  validation {
    condition = (
      !var.kyverno.enabled ||
      length(setsubtract(
        toset(concat([
          "failed to list resources",
          "failed to watch resource",
          "failed to start watcher",
          "failed to sync",
          "failed to run warmup",
          "failed to load certificate",
          "failed to update lock",
          "failed to process request",
          "failed to check permissions",
          "failed to scan resource",
          "failed to fetch data",
          "failed to substitute variables",
          "failed calling webhook",
          "leader election lost",
          "dropping request",
          "panic",
        ], var.kyverno.error_patterns_include)),
        toset(var.kyverno.error_patterns_exclude)
      )) > 0
    )
    error_message = "The combination of error_patterns_exclude and error_patterns_include results in no active message patterns. At least one pattern must remain active, otherwise the alert will not be created."
  }
}

variable "cert_manager" {
  description = "Configuration for cert-manager missing issuer log alert. Allows customization of project, cluster, namespace, notification channels, alert documentation, enablement, extra filters, auto-close timing, and notification rate limiting."
  default     = {}
  type = object({
    enabled                          = optional(bool, true)
    cluster_name                     = optional(string, null)
    project_id                       = optional(string, null)
    namespace                        = optional(string, "cert-manager")
    notification_enabled             = optional(bool, true)
    notification_channels            = optional(list(string), [])
    logmatch_notification_rate_limit = optional(string, "300s")
    alert_documentation              = optional(string, null)
    auto_close_seconds               = optional(number, 3600)
    filter_extra                     = optional(string, "")
  })

  validation {
    condition = (
      !var.cert_manager.enabled ||
      (var.cert_manager.cluster_name != null && var.cert_manager.cluster_name != "")
    )
    error_message = "When 'enabled' is true, 'cluster_name' must be provided and cannot be empty."
  }
}

variable "konnectivity_agent" {
  description = "Configuration for Konnectivity agent deployment replica alert in GKE. Triggers when there are no available replicas."
  default     = {}
  type = object({
    enabled               = optional(bool, true)
    cluster_name          = optional(string, null)
    project_id            = optional(string, null)
    namespace             = optional(string, "kube-system")
    deployment_name       = optional(string, "konnectivity-agent")
    duration_seconds      = optional(number, 60)
    auto_close_seconds    = optional(number, 3600)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    notification_prompts  = optional(list(string), null)
  })

  validation {
    condition = (
      !var.konnectivity_agent.enabled ||
      (var.konnectivity_agent.cluster_name != null && var.konnectivity_agent.cluster_name != "")
    )
    error_message = "When 'enabled' is true, 'cluster_name' must be provided and cannot be empty."
  }
}

variable "typesense" {
  description = "Configuration for Typesense monitoring alerts. Supports uptime checks for HTTP endpoints and container-level alerts (pod restarts) in GKE. Each app is identified by its name (map key)."
  default     = {}
  type = object({
    enabled               = optional(bool, false)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    cluster_name          = optional(string, null)

    apps = optional(map(object({
      uptime_check = optional(object({
        enabled = optional(bool, true)
        host    = string
        path    = optional(string, "/readyz")
      }), null)

      container_check = optional(object({
        enabled   = optional(bool, true)
        namespace = string
        pod_restart = optional(object({
          threshold            = optional(number, 0)
          alignment_period     = optional(number, 60)
          duration             = optional(number, 180)
          auto_close_seconds   = optional(number, 3600)
          notification_prompts = optional(list(string), null)
        }), {})
      }), null)
    })), {})
  })

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        trimspace(app_name) != "" &&
        (config.uptime_check != null ? try(trimspace(config.uptime_check.host), "") != "" : true) &&
        (config.container_check != null ? try(trimspace(config.container_check.namespace), "") != "" : true)
      )
    ])
    error_message = "Each app must have a non-empty name (map key). If uptime_check is provided, 'host' must be non-empty. If container_check is provided, 'namespace' must be non-empty."
  }

  validation {
    condition = (
      length([for app_name, config in var.typesense.apps : app_name if config.container_check != null]) == 0 ||
      try(trimspace(var.typesense.cluster_name), "") != ""
    )
    error_message = "When any app has container_check configured, 'cluster_name' must be provided at the typesense level."
  }
}

variable "litellm" {
  description = "Configuration for LiteLLM monitoring alerts. Supports uptime checks for HTTP endpoints and container-level alerts (pod restarts) in GKE. Each app is identified by its name (map key)."
  default     = {}
  type = object({
    enabled               = optional(bool, false)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    cluster_name          = optional(string, null)

    apps = optional(map(object({
      uptime_check = optional(object({
        enabled = optional(bool, true)
        host    = string
        path    = optional(string, "/health/readiness")
      }), null)

      container_check = optional(object({
        enabled   = optional(bool, true)
        namespace = string
        pod_restart = optional(object({
          threshold            = optional(number, 0)
          alignment_period     = optional(number, 60)
          duration             = optional(number, 180)
          auto_close_seconds   = optional(number, 3600)
          notification_prompts = optional(list(string), null)
        }), {})
      }), null)
    })), {})
  })

  validation {
    condition = alltrue([
      for app_name, config in var.litellm.apps : (
        trimspace(app_name) != "" &&
        (config.uptime_check != null ? try(trimspace(config.uptime_check.host), "") != "" : true) &&
        (config.container_check != null ? try(trimspace(config.container_check.namespace), "") != "" : true)
      )
    ])
    error_message = "Each app must have a non-empty name (map key). If uptime_check is provided, 'host' must be non-empty. If container_check is provided, 'namespace' must be non-empty."
  }

  validation {
    condition = (
      length([for app_name, config in var.litellm.apps : app_name if config.container_check != null]) == 0 ||
      try(trimspace(var.litellm.cluster_name), "") != ""
    )
    error_message = "When any app has container_check configured, 'cluster_name' must be provided at the litellm level."
  }
}

variable "memorystore" {
  description = "Configuration for GCP Memorystore (Redis) CPU monitoring alerts. Supports both Redis instances and Redis clusters with multiple threshold levels. Each resource is identified by its name (map key)."
  default     = {}
  type = object({
    enabled               = optional(bool, false)
    project_id            = optional(string, null)
    auto_close            = optional(string, "86400s") # default 24h
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])

    instances = optional(map(object({
      cpu_utilization = optional(list(object({
        severity         = optional(string, "WARNING")
        threshold        = optional(number, 0.80)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "300s")
        })), [
        {
          threshold = 0.80,
          duration  = "300s",
        },
        {
          severity  = "CRITICAL",
          threshold = 0.90,
          duration  = "300s",
        }
      ])
    })), {})

    clusters = optional(map(object({
      cpu_utilization = optional(list(object({
        severity         = optional(string, "WARNING")
        threshold        = optional(number, 0.80)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "300s")
        })), [
        {
          threshold = 0.80,
          duration  = "300s",
        },
        {
          severity  = "CRITICAL",
          threshold = 0.90,
          duration  = "300s",
        }
      ])
    })), {})
  })

  validation {
    condition = alltrue([
      for instance_name, config in var.memorystore.instances :
      trimspace(instance_name) != ""
    ])
    error_message = "Each instance must have a non-empty name (map key)."
  }

  validation {
    condition = alltrue([
      for cluster_name, config in var.memorystore.clusters :
      trimspace(cluster_name) != ""
    ])
    error_message = "Each cluster must have a non-empty name (map key)."
  }
}

variable "ssl_alert" {
  description = "Configuration for SSL certificate expiration alerts. Allows customization of project, notification channels, alert thresholds, and user labels."
  default     = {}
  type = object({
    enabled               = optional(bool, false)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    threshold_days        = optional(list(number), [15, 7])
    user_labels           = optional(map(string), {})
  })
}
