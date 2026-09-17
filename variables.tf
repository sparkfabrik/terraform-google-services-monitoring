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
  description = "Configuration for Typesense monitoring alerts. Supports uptime checks for HTTP endpoints (with optional response content assertion), container-level alerts (pod restarts), log-based alerts and workload vitals (memory, CPU, PVC volume, replica availability) in GKE. Each app is identified by its name (map key). The GKE cluster targeted by Kubernetes-based checks is the app-level 'cluster_name' when set, otherwise the service-level 'cluster_name'. Kubernetes-based checks filter on the app-level 'namespace', required when any of container_check, log_check, flood_check or workload_check is configured. Every duration-like field is a number of seconds carrying a '_seconds' name suffix. Notification routing resolves per check: each check block accepts 'notification_enabled' (tri-state, null inherits the service-level setting) and 'notification_channels' (null inherits the service-level list when non-empty, otherwise the root 'notification_channels'); the most specific non-null setting wins. When the effective 'notification_enabled' is false the check's policies are created with no notification channels; an empty override list is legal and also results in no notifications. Each app can additionally enable a per-app Cloud Monitoring dashboard ('dashboard' block): widgets are built only from the checks the app configures, the title defaults to 'Typesense vitals — <app> (cluster=..., namespace=...)' and can be overridden via 'display_name'. Apps with both 'log_check' and the dashboard enabled also get a log-based counter metric for error logs feeding the dashboard's error-log rate chart. 'log_check.exclude_patterns' is a list of substrings excluded from the log-match alert: entries whose 'jsonPayload.message' or 'textPayload' contains any pattern do not fire the alert (Cloud Logging ':' operator, case-insensitive substring match); the flood check and the dashboard error-log metric keep counting excluded entries. 'log_check.exclude_transient_errors' (default false) additionally appends a module-maintained preset of transient Typesense raft-recovery patterns ('Peer refresh failed', '> healthy write lag of', '> healthy read lag of') to the effective exclusion list, deduplicated and after the user patterns; the preset is not configurable and applies to the log-match alert only. The lag patterns also match chronic degradation, so enable the toggle only for apps that keep a health signal covered by another check ('uptime_check' or 'workload_check'), otherwise a persistent replication failure has nothing left to surface it."
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
        exclude_patterns                         = optional(list(string), [])
        exclude_transient_errors                 = optional(bool, false)
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

      # Application vitals from the Typesense Prometheus exporter, scraped into
      # Cloud Monitoring by a GMP PodMonitoring delivered out of band (Sveltos).
      # Requires that PodMonitoring: without it these series are absent and the
      # policies never fire (they also never error). Each family is a list of
      # {severity, threshold, duration_seconds}; empty the list to disable that
      # family, add entries to add policies. Defaults are deliberately loose and
      # sustained over a long window to avoid false positives on transient
      # spikes (e.g. bulk imports); tune per app once real traffic is observed.
      # PromQL is 'max by (pod) (<metric>{cluster,namespace,job="typesense"}) >
      # threshold' held for duration_seconds.
      metrics_check = optional(object({
        enabled = optional(bool, true)
        # Write queue depth (typesense_stats_pending_write_batches). Typesense
        # rejects writes at 500; defaults warn well below and only when sustained.
        write_queue = optional(list(object({
          severity         = optional(string, "WARNING")
          threshold        = optional(number, 300)
          duration_seconds = optional(number, 600)
          })), [
          { severity = "WARNING", threshold = 300 },
          { severity = "CRITICAL", threshold = 450 },
        ])
        # Requests rejected because the node is overloaded
        # (typesense_stats_overloaded_requests_per_second). Any sustained
        # non-zero rate is real; kept WARNING to avoid paging on brief spikes.
        overloaded_requests = optional(list(object({
          severity         = optional(string, "WARNING")
          threshold        = optional(number, 0)
          duration_seconds = optional(number, 600)
          })), [
          { severity = "WARNING", threshold = 0 },
        ])
        # Sustained search / write latency over a per-app SLO
        # (typesense_stats_search_latency_ms / _write_latency_ms). Off by default:
        # the threshold is per app and must be set from observed traffic. These
        # are gauges (point-in-time average), not percentiles.
        search_latency = optional(list(object({
          severity         = optional(string, "WARNING")
          threshold        = number
          duration_seconds = optional(number, 300)
        })), [])
        write_latency = optional(list(object({
          severity         = optional(string, "WARNING")
          threshold        = number
          duration_seconds = optional(number, 300)
        })), [])
        auto_close_seconds    = optional(number, 3600)
        notification_prompts  = optional(list(string), null)
        notification_enabled  = optional(bool, null)
        notification_channels = optional(list(string), null)
      }), null)

      # Per-app Cloud Monitoring dashboard. Widgets render for the checks the app
      # configures: GKE system metrics, log-based metrics, uptime checks. The
      # scraped typesense_* vitals widgets (write queue, search/write latency,
      # overloaded requests, jemalloc memory) are opt-in: they render only when
      # metrics_check is set AND 'metrics_widgets' is true. Default off, because
      # the extra widgets are not wanted on every app (e.g. stage).
      dashboard = optional(object({
        enabled         = optional(bool, true)
        display_name    = optional(string, null)
        metrics_widgets = optional(bool, false)
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
        (config.container_check == null && config.log_check == null && config.flood_check == null && config.workload_check == null && config.metrics_check == null) ||
        try(trimspace(config.namespace), "") != ""
      )
    ])
    error_message = "Each app with container_check, log_check, flood_check, workload_check or metrics_check configured must set a non-empty app-level 'namespace'."
  }

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        length(setsubtract(try(coalesce(config.log_check.notification_prompts, []), []), ["OPENED"])) == 0
      )
    ])
    error_message = "log_check.notification_prompts only supports [\"OPENED\"]: the Cloud Monitoring API rejects other prompts on log-match alert policies (closure notifications are not available for them)."
  }

  # The same predicate guards the module-maintained preset, through the
  # precondition on google_monitoring_alert_policy.typesense_logmatch_alert
  # in typesense.tf; keep both copies in sync. A null entry is rejected by
  # the conditional and not by a `pattern != null &&` conjunct: HCL does not
  # short-circuit `&&` on Terraform 1.5 (the module floor), so trimspace()
  # would still run on the null and mask this message with a function error.
  # "\\p{Cc}" is the Unicode control class: C0, C1 and DEL.
  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : alltrue([
        for pattern in try(config.log_check.exclude_patterns, []) :
        pattern == null ? false : (
          trimspace(pattern) != "" &&
          !strcontains(pattern, "\"") &&
          !strcontains(pattern, "\\") &&
          length(regexall("\\p{Cc}", pattern)) == 0
        )
      ])
    ])
    error_message = "Each log_check.exclude_patterns entry must be a non-null string, non-empty after trimming, and must not contain a double quote (\"), a backslash (\\) or a control character: patterns are embedded verbatim in the Cloud Logging filter, where a trailing backslash escapes the closing quote, a whitespace-only pattern silences every log line and a raw control character lands verbatim in the API payload and fails opaquely at apply. Check every app's log_check.exclude_patterns list."
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
          ) : [],
          config.metrics_check != null ? concat(
            [config.metrics_check.auto_close_seconds],
            flatten([
              for entry in concat(
                config.metrics_check.write_queue,
                config.metrics_check.overloaded_requests,
                config.metrics_check.search_latency,
                config.metrics_check.write_latency
              ) : [entry.duration_seconds]
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
        config.metrics_check == null ? true : alltrue([
          for entry in concat(
            config.metrics_check.write_queue,
            config.metrics_check.overloaded_requests,
            config.metrics_check.search_latency,
            config.metrics_check.write_latency
          ) : contains(["WARNING", "ERROR", "CRITICAL"], upper(entry.severity))
        ])
      )
    ])
    error_message = "Each metrics_check threshold entry (write_queue, overloaded_requests, search_latency, write_latency) must use a 'severity' of 'WARNING', 'ERROR' or 'CRITICAL' (any casing; normalized to uppercase by the module)."
  }

  validation {
    condition = alltrue([
      for app_name, config in var.typesense.apps : (
        config.metrics_check == null ? true : alltrue([
          for entry in concat(
            config.metrics_check.write_queue,
            config.metrics_check.overloaded_requests,
            config.metrics_check.search_latency,
            config.metrics_check.write_latency
          ) : entry.threshold >= 0
        ])
      )
    ])
    error_message = "Each metrics_check threshold (write_queue, overloaded_requests, search_latency, write_latency) must be >= 0: a negative threshold renders a PromQL comparison that fires permanently."
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

variable "gke_node_count" {
  description = "Configuration for the GKE total node count alert. Fires when the cluster's total node count (across all pools of 'cluster_name') stays above 'threshold' for 'duration'. Requires 'cluster_name' when enabled. Per-pool scoping is intentionally not supported: on GKE the node pool is not a queryable label on k8s_node metric series (node names truncate the pool, and kube-state-metrics is off), so a reliable per-pool count would require enabling kube-state-metrics and a PromQL condition."
  default     = {}
  type = object({
    enabled               = optional(bool, false)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    user_labels           = optional(map(string), {})
    cluster_name          = optional(string, null)
    threshold             = optional(number, 16)
    duration              = optional(string, "86400s")
    alignment_period      = optional(string, "60s")
    severity              = optional(string, "WARNING")
    auto_close            = optional(string, null)
  })

  validation {
    condition = (
      !var.gke_node_count.enabled ||
      (var.gke_node_count.cluster_name != null && var.gke_node_count.cluster_name != "")
    )
    error_message = "When 'enabled' is true, 'cluster_name' must be provided and cannot be empty."
  }
}

variable "vertex_ai" {
  description = "Configuration for Vertex AI consumption and estimated-cost observability on the publisher models of a project. Vertex AI publishes token counts to Cloud Monitoring but no spend metric, so the cost shown by this service is an estimate computed as tokens times the published list price; the authoritative figure is the BigQuery billing export. 'pricing' is the price table: one entry per model, keyed by the value of the metric's 'type' label, in USD per one million tokens, with a 'global' table for traffic on the global endpoint and an optional 'regional' table for regional and multi-region endpoints (null falls back to the global table). Models absent from the table stay visible in the consumption widgets and contribute nothing to the estimate. 'models' narrows the cost estimate to a subset of the priced models; null uses them all. The service, the dashboard and each alert family are enabled independently and every one of them is off by default. 'alerts.cost.thresholds' is a map of named thresholds and each entry becomes its own alert policy, so a warning level and a critical level raise distinguishable incidents. 'alerts.error_rate' watches the share of invocations answered with a given response code, 429 by default; note that on Gemini pay-as-you-go a 429 means contention on a shared resource and not an exhausted quota, so the alert is informative and has no quota increase as a remedy. Notification routing resolves per alert: 'notification_channels' on the alert inherits the service-level list when null, which in turn inherits the root list when empty. Every duration-like field is a number of seconds carrying a '_seconds' name suffix."
  default     = {}
  type = object({
    enabled               = optional(bool, false)
    project_id            = optional(string, null)
    notification_enabled  = optional(bool, true)
    notification_channels = optional(list(string), [])
    models                = optional(list(string), null)

    # Date the price table was last checked against the published list, shown on
    # the dashboard next to the estimate. Override it together with 'pricing':
    # a project that supplies its own prices owns its own verification date.
    pricing_verified_on = optional(string, "2026-09-17")

    # USD per 1M tokens, keyed by the metric's 'type' label value.
    #
    # MAINTAINED BY HAND, AND IT MUST BE REVIEWED PERIODICALLY.
    #
    # Google publishes no price API that covers every model here: Anthropic
    # models have no SKU at all in the Cloud Billing Catalog and the embedding
    # SKU cannot be identified from it, so nothing can read this table for you
    # and nothing will tell you when it is wrong. A stale price produces a
    # confident wrong cost with no error and no visible symptom.
    #
    # Put the review on a recurring issue, not on a trigger, and re-inventory
    # the live token_count series each time: a model routed through the gateway
    # after this table was written shows up in the token widgets and silently
    # contributes nothing to the estimate. See the README for the full rationale.
    #
    # The model set was taken from the live token_count series of a real project
    # over 40 days, not from the models someone remembered were in use: two of
    # the entries below were already serving traffic before anyone listed them.
    #
    # Verified against the Google pricing page on 2026-09-16 (gemini-3.5-flash,
    # gemini-3-flash-preview, gemini-embedding-001, claude-sonnet-4-6) and on
    # 2026-09-17 (gemini-3.7-flash, claude-sonnet-5), cross-checked with the
    # Cloud Billing Catalog API where a SKU exists. SKU ids to diff a Gemini
    # price against:
    #   gemini-3.5-flash       global  input 9733-FF95-45E3, output 4E73-15BD-0D78
    #   gemini-3-flash-preview global  input 7EBE-3B46-F75C, output 0127-F0B7-365E
    #
    # Regional and multi-region endpoints carry a 10% premium over the global one.
    # The published values are rounded, so the regional table holds them verbatim
    # instead of applying a multiplier.
    #
    # The cache_* token types are observed on the Anthropic series but are not
    # documented: the metric descriptor only defines input and output.
    pricing = optional(map(object({
      global   = map(number)
      regional = optional(map(number), null)
      })), {
      "gemini-3.5-flash" = {
        global   = { input = 1.50, output = 9.00 }
        regional = { input = 1.65, output = 9.90 }
      }
      "gemini-3-flash-preview" = {
        global = { input = 0.50, output = 3.00 }
      }
      # INTRODUCTORY PRICING, EXPIRES 2026-12-31. From 2027-01-01 the published
      # standard price doubles to 1.50 / 7.50 global and 1.65 / 8.25 regional.
      # Nothing switches these values automatically: change them by hand on that
      # date, or the estimate silently halves the real spend of this model.
      "gemini-3.7-flash" = {
        global   = { input = 0.75, output = 3.75 }
        regional = { input = 0.825, output = 4.125 }
      }
      # Served only from single regions: the live 'source' label is a region name
      # such as us-central1 or europe-west8, never 'global'. No regional column is
      # published for embeddings, and the 10% non-global premium is scoped to the
      # GA Gemini 3+ generative families, so regional traffic is correctly priced
      # at the same rate. Watch for a "Non-global" row appearing in the embedding
      # pricing table, which is what would change this.
      "gemini-embedding-001" = {
        global = { input = 0.15, output = 0 }
      }
      "claude-sonnet-4-6" = {
        global = {
          input                = 3.00
          output               = 15.00
          cache_read_input     = 0.30
          cache_write_input    = 3.75
          cache_write_1h_input = 6.00
        }
        regional = {
          input                = 3.30
          output               = 16.50
          cache_read_input     = 0.33
          cache_write_input    = 4.13
          cache_write_1h_input = 6.60
        }
      }
      "claude-sonnet-5" = {
        global = {
          input                = 2.00
          output               = 10.00
          cache_read_input     = 0.20
          cache_write_input    = 2.50
          cache_write_1h_input = 4.00
        }
        regional = {
          input                = 2.20
          output               = 11.00
          cache_read_input     = 0.22
          cache_write_input    = 2.75
          cache_write_1h_input = 4.40
        }
      }
    })

    dashboard = optional(object({
      enabled      = optional(bool, true)
      display_name = optional(string, null)
      cost_widgets = optional(bool, true)
    }), {})

    alerts = optional(object({
      cost = optional(object({
        enabled = optional(bool, true)
        # Always declared by the consumer. A monetary amount is a budget, and
        # only the project that owns the spend knows it: unlike a utilisation
        # ratio it does not transfer between projects, so the module ships none
        # and no cost alert exists until one is declared here. Each entry becomes
        # its own alert policy, so a warning and a critical raise distinguishable
        # incidents. Set an entry to 'enabled = false' to silence it without
        # deleting it.
        thresholds = optional(map(object({
          enabled                     = optional(bool, true)
          threshold_usd               = number
          window_seconds              = optional(number, 86400)
          duration_seconds            = optional(number, 0)
          evaluation_interval_seconds = optional(number, 300)
          severity                    = optional(string, null)
          notification_enabled        = optional(bool, null)
          notification_channels       = optional(list(string), null)
          notification_prompts        = optional(list(string), ["OPENED"])
          auto_close_seconds          = optional(number, 86400)
        })), {})
      }), {})

      error_rate = optional(object({
        enabled                     = optional(bool, true)
        response_code               = optional(string, "429")
        threshold_ratio             = optional(number, 0.01)
        window_seconds              = optional(number, 60)
        duration_seconds            = optional(number, 300)
        evaluation_interval_seconds = optional(number, 60)
        severity                    = optional(string, null)
        notification_enabled        = optional(bool, null)
        notification_channels       = optional(list(string), null)
        notification_prompts        = optional(list(string), ["OPENED"])
        auto_close_seconds          = optional(number, 3600)
      }), {})
    }), {})
  })

  validation {
    condition = alltrue([
      for model_name, config in var.vertex_ai.pricing :
      trimspace(model_name) != "" && length(config.global) > 0
    ])
    error_message = "Each pricing entry must have a non-empty model name (map key) and at least one price in its global table."
  }

  validation {
    condition = alltrue(flatten([
      for model_name, config in var.vertex_ai.pricing : [
        for token_type, price in merge(config.global, coalesce(config.regional, {})) : price >= 0
      ]
    ]))
    error_message = "Prices must be zero or positive."
  }

  validation {
    condition = alltrue([
      for name, threshold in var.vertex_ai.alerts.cost.thresholds :
      threshold.threshold_usd > 0 && threshold.window_seconds >= 60
    ])
    error_message = "A cost threshold must set a positive threshold_usd and a window_seconds of at least 60."
  }


  validation {
    condition     = var.vertex_ai.alerts.error_rate.threshold_ratio > 0 && var.vertex_ai.alerts.error_rate.threshold_ratio <= 1
    error_message = "The error_rate threshold_ratio is a share of the invocations and must be greater than 0 and at most 1."
  }

  validation {
    condition     = var.vertex_ai.models == null ? true : length(var.vertex_ai.models) > 0
    error_message = "When set, models must list at least one model; use null to price every model in the table."
  }
}
