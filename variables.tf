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
  description = "Configuration for Kyverno monitoring. Provisions a level-1 admission-controller restart alert, two tiers of service-error alerts (tier 1 filtered against measured noise, tier 2 volume catch-all) and a broken-policy engine alert. All alerts inherit the module notification channels unless overridden. Thresholds stay configurable per cluster."
  default     = {}
  type = object({
    enabled               = optional(bool, true)
    cluster_name          = optional(string, null)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    alert_documentation   = optional(string, null)
    namespace             = optional(string, "kyverno")

    # Level 1 — admission controller pod restarts (system metric restart_count).
    restart_check = optional(object({
      enabled              = optional(bool, true)
      threshold            = optional(number, 0)
      alignment_period     = optional(number, 60)
      duration             = optional(number, 60)
      auto_close_seconds   = optional(number, 3600)
      notification_prompts = optional(list(string), null)
    }), {})

    # Tier 1 — service errors: ERROR logs minus the measured noise classes, minus the engine logger.
    # threshold > value within alignment_period (default > 5 in 10 min).
    service_errors_check = optional(object({
      enabled            = optional(bool, true)
      threshold          = optional(number, 5)
      alignment_period   = optional(number, 600)
      duration           = optional(number, 0)
      auto_close_seconds = optional(number, 3600)
      # Noise classes excluded from tier 1, matched on jsonPayload.message OR jsonPayload.error.
      noise_exclusions = optional(list(string), [
        "failed to update lock optimistically",
        "context canceled",
        "context deadline exceeded",
        "stale GroupVersion discovery",
        "the server is currently unable to handle the request",
        "leader election lost",
        "http: Server closed",
        "Operation cannot be fulfilled on",
        "error reading from server",
        "connection reset by peer",
        "connection force closed",
        "connection refused",
        "http2: client connection lost",
        "use of closed network connection",
        "failed to delete ephemeral report",
      ])
    }), {})

    # Tier 2 — volume catch-all: same source as tier 1, no exclusions, minus the engine logger.
    # threshold > value per alignment_period sustained for duration (default > 10/min for 15 min).
    volume_check = optional(object({
      enabled            = optional(bool, true)
      threshold          = optional(number, 10)
      alignment_period   = optional(number, 60)
      duration           = optional(number, 900)
      auto_close_seconds = optional(number, 3600)
    }), {})

    # Engine — broken policies: engine-logger ERROR logs, one incident per policy.
    # threshold > value sustained for duration (default > 0 for 5 min).
    engine_check = optional(object({
      enabled            = optional(bool, true)
      threshold          = optional(number, 0)
      alignment_period   = optional(number, 60)
      duration           = optional(number, 300)
      auto_close_seconds = optional(number, 3600)
    }), {})

    # Policy review dashboard (google_monitoring_dashboard). Section A — violated
    # policies from PolicyViolation events (Log Analytics SQL widgets); Section B —
    # error-producing policies from engine ERROR logs. Requires Log Analytics enabled
    # on the project's _Default bucket (prerequisite for the SQL widgets).
    dashboard = optional(object({
      enabled = optional(bool, true)
      # Rolling window (hours) for the "current state" widgets; the background scan
      # re-emits persistent violations roughly hourly, so 25h covers the current state.
      window_hours = optional(number, 25)
    }), {})
  })

  validation {
    condition = (
      !var.kyverno.enabled ||
      (var.kyverno.cluster_name == null ? false : trimspace(var.kyverno.cluster_name) != "")
    )
    error_message = "When 'enabled' is true, 'cluster_name' must be provided and cannot be empty or whitespace-only."
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
  description = "Configuration for Typesense monitoring alerts. Supports uptime checks for HTTP endpoints (with optional response content assertion), container-level alerts (pod restarts), log-based alerts and workload vitals (memory, CPU, PVC volume, replica availability) in GKE. Each app is identified by its name (map key). The GKE cluster targeted by Kubernetes-based checks is the app-level 'cluster_name' when set, otherwise the service-level 'cluster_name'. Kubernetes-based checks filter on the app-level 'namespace', required when any of container_check, log_check, flood_check or workload_check is configured. Every duration-like field is a number of seconds carrying a '_seconds' name suffix. Notification routing resolves per check: each check block accepts 'notification_enabled' (tri-state, null inherits the service-level setting) and 'notification_channels' (null inherits the service-level list when non-empty, otherwise the root 'notification_channels'); the most specific non-null setting wins. When the effective 'notification_enabled' is false the check's policies are created with no notification channels; an empty override list is legal and also results in no notifications. Each app can additionally enable a per-app Cloud Monitoring dashboard ('dashboard' block): widgets are built only from the checks the app configures, the title defaults to 'Typesense vitals — <app> (cluster=..., namespace=...)' and can be overridden via 'display_name'. Apps with both 'log_check' and the dashboard enabled also get a log-based counter metric for error logs feeding the dashboard's error-log rate chart."
  default     = {}
  type = object({
    enabled               = optional(bool, false)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    cluster_name          = optional(string, null)
    alert_documentation   = optional(string, null)

    apps = optional(map(object({
      cluster_name = optional(string, null)
      namespace    = optional(string, null)

      uptime_check = optional(object({
        enabled               = optional(bool, true)
        host                  = string
        path                  = optional(string, "/readyz")
        content_match         = optional(string, null)
        notification_enabled  = optional(bool, null)
        notification_channels = optional(list(string), null)
      }), null)

      container_check = optional(object({
        enabled               = optional(bool, true)
        notification_enabled  = optional(bool, null)
        notification_channels = optional(list(string), null)
        pod_restart = optional(object({
          threshold                = optional(number, 0)
          alignment_period_seconds = optional(number, 60)
          duration_seconds         = optional(number, 180)
          auto_close_seconds       = optional(number, 3600)
          notification_prompts     = optional(list(string), null)
        }), {})
      }), null)

      log_check = optional(object({
        enabled                                  = optional(bool, true)
        min_severity                             = optional(string, "ERROR")
        logmatch_notification_rate_limit_seconds = optional(number, 300)
        auto_close_seconds                       = optional(number, 3600)
        notification_enabled                     = optional(bool, null)
        notification_channels                    = optional(list(string), null)
        notification_prompts                     = optional(list(string), null)
      }), null)

      flood_check = optional(object({
        enabled                      = optional(bool, true)
        threshold_entries_per_minute = optional(number, 1000)
        alignment_period_seconds     = optional(number, 60)
        duration_seconds             = optional(number, 300)
        auto_close_seconds           = optional(number, 86400)
        notification_enabled         = optional(bool, null)
        notification_channels        = optional(list(string), null)
        notification_prompts         = optional(list(string), null)
      }), null)

      # Workload vitals: saturation and availability alerts built on free GKE
      # system metrics. Requires containers to declare resource limits
      # (limit_utilization has no series otherwise). Each threshold family is
      # disabled by emptying its list; replica alerts via replica_availability.enabled.
      workload_check = optional(object({
        enabled           = optional(bool, true)
        expected_replicas = number
        container_name    = optional(string, "typesense")
        # Disambiguates multiple TypesenseClusters sharing a namespace
        # (top-level controller name, e.g. the operator-generated StatefulSet).
        controller_name = optional(string, null)
        # PVC volume to watch; "data" is the Typesense operator's PVC template name.
        volume_name = optional(string, "data")
        memory_utilization = optional(list(object({
          severity                 = optional(string, "WARNING")
          threshold                = optional(number, 0.85)
          alignment_period_seconds = optional(number, 300)
          duration_seconds         = optional(number, 300)
          })), [
          {
            severity  = "WARNING",
            threshold = 0.85,
          },
          {
            severity  = "CRITICAL",
            threshold = 0.95,
          }
        ])
        cpu_utilization = optional(list(object({
          severity                 = optional(string, "WARNING")
          threshold                = optional(number, 0.90)
          alignment_period_seconds = optional(number, 300)
          duration_seconds         = optional(number, 300)
          })), [
          {
            severity  = "WARNING",
            threshold = 0.90,
          }
        ])
        volume_utilization = optional(list(object({
          severity                 = optional(string, "WARNING")
          threshold                = optional(number, 0.75)
          alignment_period_seconds = optional(number, 300)
          duration_seconds         = optional(number, 300)
          })), [
          {
            severity  = "WARNING",
            threshold = 0.75,
          },
          {
            severity  = "CRITICAL",
            threshold = 0.85,
          }
        ])
        replica_availability = optional(object({
          enabled          = optional(bool, true)
          duration_seconds = optional(number, 300)
        }), {})
        auto_close_seconds    = optional(number, 3600)
        notification_prompts  = optional(list(string), null)
        notification_enabled  = optional(bool, null)
        notification_channels = optional(list(string), null)
      }), null)

      # Per-app Cloud Monitoring dashboard built from the metrics the module
      # already wires (GKE system metrics, log-based metrics, uptime checks).
      # Widgets render only for the checks the app configures.
      dashboard = optional(object({
        enabled      = optional(bool, true)
        display_name = optional(string, null)
      }), null)
    })), {})
  })

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        trimspace(app_name) != "" &&
        (config.uptime_check != null ? try(trimspace(config.uptime_check.host), "") != "" : true)
      )
    ])
    error_message = "Each app must have a non-empty name (map key). If uptime_check is provided, 'host' must be non-empty."
  }

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        (config.container_check == null && config.log_check == null && config.flood_check == null && config.workload_check == null) ||
        try(trimspace(config.namespace), "") != ""
      )
    ])
    error_message = "Each app with container_check, log_check, flood_check or workload_check configured must set a non-empty app-level 'namespace'."
  }

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : alltrue([
        for value in concat(
          config.container_check != null ? [
            config.container_check.pod_restart.alignment_period_seconds,
            config.container_check.pod_restart.duration_seconds,
            config.container_check.pod_restart.auto_close_seconds,
          ] : [],
          config.log_check != null ? [
            config.log_check.logmatch_notification_rate_limit_seconds,
            config.log_check.auto_close_seconds,
          ] : [],
          config.flood_check != null ? [
            config.flood_check.alignment_period_seconds,
            config.flood_check.duration_seconds,
            config.flood_check.auto_close_seconds,
          ] : [],
          config.workload_check != null ? concat(
            [
              config.workload_check.replica_availability.duration_seconds,
              config.workload_check.auto_close_seconds,
            ],
            flatten([
              for entry in concat(
                config.workload_check.memory_utilization,
                config.workload_check.cpu_utilization,
                config.workload_check.volume_utilization
              ) : [entry.alignment_period_seconds, entry.duration_seconds]
            ])
          ) : []
        ) : value > 0
      ])
    ])
    error_message = "Every '_seconds' timing field (alignment_period_seconds, duration_seconds, auto_close_seconds, logmatch_notification_rate_limit_seconds) must be a positive number of seconds."
  }

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        config.workload_check == null || try(config.workload_check.expected_replicas >= 1, false)
      )
    ])
    error_message = "If workload_check is provided, 'expected_replicas' must be >= 1."
  }

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        config.workload_check == null ? true : alltrue([
          for entry in concat(
            config.workload_check.memory_utilization,
            config.workload_check.cpu_utilization,
            config.workload_check.volume_utilization
          ) : contains(["WARNING", "ERROR", "CRITICAL"], upper(entry.severity))
        ])
      )
    ])
    error_message = "Each workload_check threshold entry must use a 'severity' of 'WARNING', 'ERROR' or 'CRITICAL' (any casing; normalized to uppercase by the module)."
  }

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        (config.container_check == null && config.log_check == null && config.flood_check == null && config.workload_check == null) ||
        try(trimspace(coalesce(config.cluster_name, var.typesense.cluster_name)), "") != ""
      )
    ])
    error_message = "Each app with container_check, log_check, flood_check or workload_check configured must have a resolvable GKE cluster name: set 'cluster_name' on the app or at the typesense level."
  }

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        config.dashboard == null ||
        config.uptime_check != null ||
        config.container_check != null ||
        config.log_check != null ||
        config.flood_check != null ||
        config.workload_check != null
      )
    ])
    error_message = "Each app with 'dashboard' configured must define at least one check (uptime_check, container_check, log_check, flood_check or workload_check): a dashboard without checks has nothing to render."
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
  description = "Configuration for GCP Memorystore (Redis) CPU and memory utilization monitoring alerts. Supports both Redis instances and Redis clusters with multiple threshold levels. Each resource is identified by its name (map key)."
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
        })), []
      )
      memory_utilization = optional(list(object({
        severity         = optional(string, "WARNING")
        threshold        = optional(number, 0.80)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "300s")
        })), [
        {
          severity  = "CRITICAL",
          threshold = 0.80,
        }
      ])
    })), {})

    clusters = optional(map(object({
      cpu_utilization = optional(list(object({
        severity         = optional(string, "WARNING")
        threshold        = optional(number, 0.80)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "300s")
        })), []
      )
      memory_utilization = optional(list(object({
        severity         = optional(string, "WARNING")
        threshold        = optional(number, 0.80)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "300s")
        })), [
        {
          severity  = "CRITICAL",
          threshold = 0.80,
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
