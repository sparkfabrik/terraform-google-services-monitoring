locals {
  typesense_project = var.typesense.project_id != null ? var.typesense.project_id : var.project_id

  # Per-app-per-check notification routing. The most specific non-null
  # setting wins: check-level notification_enabled/notification_channels,
  # then the service level, then the root notification_channels. A check
  # resolving to disabled gets an empty list; an empty override list is
  # legal and also means no notifications. All five keys exist for every
  # app (null checks resolve to []), so lookups never depend on the
  # policy for_each filters staying aligned with this map.
  typesense_check_notification_channels = {
    for app_name, config in var.typesense.apps :
    app_name => {
      for check_name, check in {
        uptime_check    = config.uptime_check
        container_check = config.container_check
        log_check       = config.log_check
        flood_check     = config.flood_check
        workload_check  = config.workload_check
      } :
      check_name => (
        check == null ? [] : (
          coalesce(check.notification_enabled, var.typesense.notification_enabled) ? (
            check.notification_channels != null
            ? check.notification_channels
            : (length(var.typesense.notification_channels) > 0 ? var.typesense.notification_channels : var.notification_channels)
          ) : []
        )
      )
    }
  }

  # Per-app GKE cluster resolution: app-level override wins, service-level
  # value is the fallback. Apps without any Kubernetes-based check may
  # resolve to null (validated in variables.tf otherwise).
  typesense_cluster_names = {
    for app_name, config in var.typesense.apps :
    app_name => try(coalesce(config.cluster_name, var.typesense.cluster_name), null)
  }

  # App-level namespace, shared by every Kubernetes-based check of the app.
  # Apps without any Kubernetes-based check may resolve to null (validated
  # in variables.tf otherwise).
  typesense_namespaces = {
    for app_name, config in var.typesense.apps :
    app_name => config.namespace
  }

  typesense_uptime_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config.uptime_check
    if config.uptime_check != null && try(config.uptime_check.enabled, false)
  } : {}

  typesense_container_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config.container_check
    if config.container_check != null && try(config.container_check.enabled, false)
  } : {}

  typesense_log_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config.log_check
    if config.log_check != null && try(config.log_check.enabled, false)
  } : {}

  typesense_flood_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config.flood_check
    if config.flood_check != null && try(config.flood_check.enabled, false)
  } : {}

  # Threshold severities are accepted in any casing and normalized to
  # uppercase here, before the flattened maps below, so for_each keys,
  # display names and the policy severity attribute all share one
  # canonical value.
  typesense_workload_checks = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => merge(config.workload_check, {
      memory_utilization = [
        for entry in config.workload_check.memory_utilization :
        merge(entry, { severity = upper(entry.severity) })
      ]
      cpu_utilization = [
        for entry in config.workload_check.cpu_utilization :
        merge(entry, { severity = upper(entry.severity) })
      ]
      volume_utilization = [
        for entry in config.workload_check.volume_utilization :
        merge(entry, { severity = upper(entry.severity) })
      ]
    })
    if config.workload_check != null && try(config.workload_check.enabled, false)
  } : {}

  # Flattened threshold-family maps, one alert policy per entry,
  # keyed <app>--<severity>--<threshold> (cloud_sql pattern).
  typesense_workload_memory_utilization = {
    for item in flatten([
      for app_name, wc in local.typesense_workload_checks : [
        for memory_utilization in wc.memory_utilization :
        merge(
          {
            app                   = app_name
            cluster_name          = local.typesense_cluster_names[app_name]
            namespace             = local.typesense_namespaces[app_name]
            container_name        = wc.container_name
            controller_name       = wc.controller_name
            auto_close_seconds    = wc.auto_close_seconds
            notification_prompts  = wc.notification_prompts
            notification_channels = local.typesense_check_notification_channels[app_name].workload_check
          },
          memory_utilization
        )
      ]
    ]) : "${item.app}--${item.severity}--${item.threshold}" => item
  }

  typesense_workload_cpu_utilization = {
    for item in flatten([
      for app_name, wc in local.typesense_workload_checks : [
        for cpu_utilization in wc.cpu_utilization :
        merge(
          {
            app                   = app_name
            cluster_name          = local.typesense_cluster_names[app_name]
            namespace             = local.typesense_namespaces[app_name]
            container_name        = wc.container_name
            controller_name       = wc.controller_name
            auto_close_seconds    = wc.auto_close_seconds
            notification_prompts  = wc.notification_prompts
            notification_channels = local.typesense_check_notification_channels[app_name].workload_check
          },
          cpu_utilization
        )
      ]
    ]) : "${item.app}--${item.severity}--${item.threshold}" => item
  }

  typesense_workload_volume_utilization = {
    for item in flatten([
      for app_name, wc in local.typesense_workload_checks : [
        for volume_utilization in wc.volume_utilization :
        merge(
          {
            app                   = app_name
            cluster_name          = local.typesense_cluster_names[app_name]
            namespace             = local.typesense_namespaces[app_name]
            controller_name       = wc.controller_name
            volume_name           = wc.volume_name
            auto_close_seconds    = wc.auto_close_seconds
            notification_prompts  = wc.notification_prompts
            notification_channels = local.typesense_check_notification_channels[app_name].workload_check
          },
          volume_utilization
        )
      ]
    ]) : "${item.app}--${item.severity}--${item.threshold}" => item
  }

  # Raft quorum per app: floor(n/2) + 1.
  typesense_workload_replica_quorums = {
    for app_name, wc in local.typesense_workload_checks :
    app_name => floor(wc.expected_replicas / 2) + 1
  }

  # Replica availability policies: CRITICAL below quorum, WARNING below the
  # expected count. The WARNING policy is skipped when it would duplicate the
  # CRITICAL one (expected_replicas == quorum, e.g. a single replica).
  typesense_workload_replicas = merge([
    for app_name, wc in local.typesense_workload_checks :
    merge(
      {
        "${app_name}--CRITICAL" = {
          app                   = app_name
          severity              = "CRITICAL"
          min_count             = local.typesense_workload_replica_quorums[app_name]
          reason                = "raft quorum"
          cluster_name          = local.typesense_cluster_names[app_name]
          namespace             = local.typesense_namespaces[app_name]
          container_name        = wc.container_name
          controller_name       = wc.controller_name
          duration_seconds      = wc.replica_availability.duration_seconds
          auto_close_seconds    = wc.auto_close_seconds
          notification_prompts  = wc.notification_prompts
          notification_channels = local.typesense_check_notification_channels[app_name].workload_check
        }
      },
      wc.expected_replicas > local.typesense_workload_replica_quorums[app_name] ? {
        "${app_name}--WARNING" = {
          app                   = app_name
          severity              = "WARNING"
          min_count             = wc.expected_replicas
          reason                = "expected replicas"
          cluster_name          = local.typesense_cluster_names[app_name]
          namespace             = local.typesense_namespaces[app_name]
          container_name        = wc.container_name
          controller_name       = wc.controller_name
          duration_seconds      = wc.replica_availability.duration_seconds
          auto_close_seconds    = wc.auto_close_seconds
          notification_prompts  = wc.notification_prompts
          notification_channels = local.typesense_check_notification_channels[app_name].workload_check
        }
      } : {}
    ) if wc.replica_availability.enabled
  ]...)
}

module "typesense_uptime_checks" {
  for_each = local.typesense_uptime_checks

  source                      = "./modules/http_monitoring"
  gcp_project_id              = local.typesense_project
  uptime_monitoring_host      = each.value.host
  uptime_monitoring_path      = each.value.path
  alert_notification_channels = local.typesense_check_notification_channels[each.key].uptime_check
  alert_threshold_value       = 1
  uptime_check_period         = "900s"
  alert_documentation         = var.typesense.alert_documentation
  content_matchers = each.value.content_match != null ? [
    {
      content = each.value.content_match
      matcher = "CONTAINS_STRING"
    }
  ] : []
}

# Alert: GKE Pod Restarts
# This alert monitors the restart count of Typesense containers in GKE.
# It triggers when the delta of restarts is greater than the threshold
# within the specified alignment period.
resource "google_monitoring_alert_policy" "typesense_pod_restart" {
  for_each = local.typesense_container_checks

  project      = local.typesense_project
  display_name = "Typesense Pod Restarts (cluster=${local.typesense_cluster_names[each.key]}, namespace=${local.typesense_namespaces[each.key]}, app=${each.key})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Typesense container restart count > ${each.value.pod_restart.threshold}"

    condition_threshold {
      filter = <<-EOT
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.typesense_project}"
        AND resource.labels.cluster_name="${local.typesense_cluster_names[each.key]}"
        AND resource.labels.namespace_name="${local.typesense_namespaces[each.key]}"
        AND metric.type="kubernetes.io/container/restart_count"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.pod_restart.threshold
      duration        = "${each.value.pod_restart.duration_seconds}s"

      aggregations {
        alignment_period     = "${each.value.pod_restart.alignment_period_seconds}s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "metadata.user_labels.app",
        ]
      }

      trigger {
        count = 1
      }
    }
  }

  dynamic "documentation" {
    for_each = var.typesense.alert_documentation != null ? [var.typesense.alert_documentation] : []

    content {
      content   = documentation.value
      mime_type = "text/markdown"
    }
  }

  notification_channels = local.typesense_check_notification_channels[each.key].container_check

  alert_strategy {
    auto_close           = "${each.value.pod_restart.auto_close_seconds}s"
    notification_prompts = each.value.pod_restart.notification_prompts
  }
}

# Alert: Typesense Log Errors
# This alert monitors Cloud Logging for Typesense container logs at or above
# a configurable severity threshold. It fires on the first matching log entry,
# with notification rate limiting to prevent alert fatigue.
resource "google_monitoring_alert_policy" "typesense_logmatch_alert" {
  for_each = local.typesense_log_checks

  project      = local.typesense_project
  display_name = "Typesense ERROR logs (cluster=${local.typesense_cluster_names[each.key]}, namespace=${local.typesense_namespaces[each.key]}, app=${each.key})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Typesense log severity >= ${each.value.min_severity}"
    condition_matched_log {
      filter = <<-EOT
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.typesense_project}"
        AND resource.labels.cluster_name="${local.typesense_cluster_names[each.key]}"
        AND resource.labels.namespace_name="${local.typesense_namespaces[each.key]}"
        AND resource.labels.container_name="typesense"
        AND severity>="${each.value.min_severity}"
      EOT
    }
  }

  dynamic "documentation" {
    for_each = var.typesense.alert_documentation != null ? [var.typesense.alert_documentation] : []

    content {
      content   = documentation.value
      mime_type = "text/markdown"
    }
  }

  notification_channels = local.typesense_check_notification_channels[each.key].log_check

  alert_strategy {
    auto_close = "${each.value.auto_close_seconds}s"
    notification_rate_limit {
      period = "${each.value.logmatch_notification_rate_limit_seconds}s"
    }
  }
}

# Metric: Typesense Log Volume
# User-defined log-based counter metric counting all log entries from the
# Typesense container in a given namespace. Used by the flood alert below.
resource "google_logging_metric" "typesense_log_flood" {
  for_each = local.typesense_flood_checks

  project = local.typesense_project
  name    = "typesense_log_volume_${each.key}"

  filter = <<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.typesense_project}"
    AND resource.labels.cluster_name="${local.typesense_cluster_names[each.key]}"
    AND resource.labels.namespace_name="${local.typesense_namespaces[each.key]}"
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Typesense log entry count (cluster=${local.typesense_cluster_names[each.key]}, namespace=${local.typesense_namespaces[each.key]}, app=${each.key})"
  }
}

# Alert: Typesense Log Flood
# Fires when the Typesense container log entry rate (entries/minute) exceeds
# the configured threshold over the configured duration. Designed to catch
# Raft consensus storms and similar log-flooding failure modes before they
# impact billing.
resource "google_monitoring_alert_policy" "typesense_flood_alert" {
  for_each = local.typesense_flood_checks

  project      = local.typesense_project
  display_name = "Typesense log flood (cluster=${local.typesense_cluster_names[each.key]}, namespace=${local.typesense_namespaces[each.key]}, app=${each.key})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Typesense log rate > ${each.value.threshold_entries_per_minute} entries/min"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.typesense_log_flood[each.key].name}\" AND resource.type=\"global\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold_entries_per_minute
      duration        = "${each.value.duration_seconds}s"

      aggregations {
        alignment_period   = "${each.value.alignment_period_seconds}s"
        per_series_aligner = "ALIGN_RATE"
      }

      trigger {
        count = 1
      }
    }
  }

  dynamic "documentation" {
    for_each = var.typesense.alert_documentation != null ? [var.typesense.alert_documentation] : []

    content {
      content   = documentation.value
      mime_type = "text/markdown"
    }
  }

  notification_channels = local.typesense_check_notification_channels[each.key].flood_check

  # notification_rate_limit is only accepted by the API on condition_matched_log
  # policies; this policy uses condition_threshold, so none is set here.
  alert_strategy {
    auto_close = "${each.value.auto_close_seconds}s"
  }

  depends_on = [google_logging_metric.typesense_log_flood]
}

# Alert: Typesense Container Memory Limit Utilization
# One policy per workload_check.memory_utilization entry. Thresholds the
# non-evictable working set against the container memory limit, so alerts
# survive vertical scaling. Requires the container to declare a memory limit.
resource "google_monitoring_alert_policy" "typesense_workload_memory" {
  for_each = local.typesense_workload_memory_utilization

  project      = local.typesense_project
  display_name = "Typesense memory limit utilization ${each.value.severity} ${each.value.threshold * 100}% (cluster=${each.value.cluster_name}, namespace=${each.value.namespace}, app=${each.value.app})"
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = true

  conditions {
    display_name = "Typesense container memory limit utilization > ${each.value.threshold * 100}%"

    condition_threshold {
      filter = join("\n", compact([
        "resource.type=\"k8s_container\"",
        "AND resource.labels.project_id=\"${local.typesense_project}\"",
        "AND resource.labels.cluster_name=\"${each.value.cluster_name}\"",
        "AND resource.labels.namespace_name=\"${each.value.namespace}\"",
        "AND resource.labels.container_name=\"${each.value.container_name}\"",
        "AND metric.type=\"kubernetes.io/container/memory/limit_utilization\"",
        "AND metric.labels.memory_type=\"non-evictable\"",
        each.value.controller_name != null ? "AND metadata.system_labels.top_level_controller_name=\"${each.value.controller_name}\"" : "",
      ]))

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "${each.value.duration_seconds}s"

      aggregations {
        alignment_period   = "${each.value.alignment_period_seconds}s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  dynamic "documentation" {
    for_each = var.typesense.alert_documentation != null ? [var.typesense.alert_documentation] : []

    content {
      content   = documentation.value
      mime_type = "text/markdown"
    }
  }

  notification_channels = each.value.notification_channels

  alert_strategy {
    auto_close           = "${each.value.auto_close_seconds}s"
    notification_prompts = each.value.notification_prompts
  }
}

# Alert: Typesense Container CPU Limit Utilization
# One policy per workload_check.cpu_utilization entry. Requires the container
# to declare a CPU limit.
resource "google_monitoring_alert_policy" "typesense_workload_cpu" {
  for_each = local.typesense_workload_cpu_utilization

  project      = local.typesense_project
  display_name = "Typesense CPU limit utilization ${each.value.severity} ${each.value.threshold * 100}% (cluster=${each.value.cluster_name}, namespace=${each.value.namespace}, app=${each.value.app})"
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = true

  conditions {
    display_name = "Typesense container CPU limit utilization > ${each.value.threshold * 100}%"

    condition_threshold {
      filter = join("\n", compact([
        "resource.type=\"k8s_container\"",
        "AND resource.labels.project_id=\"${local.typesense_project}\"",
        "AND resource.labels.cluster_name=\"${each.value.cluster_name}\"",
        "AND resource.labels.namespace_name=\"${each.value.namespace}\"",
        "AND resource.labels.container_name=\"${each.value.container_name}\"",
        "AND metric.type=\"kubernetes.io/container/cpu/limit_utilization\"",
        each.value.controller_name != null ? "AND metadata.system_labels.top_level_controller_name=\"${each.value.controller_name}\"" : "",
      ]))

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "${each.value.duration_seconds}s"

      aggregations {
        alignment_period   = "${each.value.alignment_period_seconds}s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  dynamic "documentation" {
    for_each = var.typesense.alert_documentation != null ? [var.typesense.alert_documentation] : []

    content {
      content   = documentation.value
      mime_type = "text/markdown"
    }
  }

  notification_channels = each.value.notification_channels

  alert_strategy {
    auto_close           = "${each.value.auto_close_seconds}s"
    notification_prompts = each.value.notification_prompts
  }
}

# Alert: Typesense PVC Volume Utilization
# One policy per workload_check.volume_utilization entry. Thresholds the pod
# volume utilization of the data PVC (raft log growth while a peer is down
# fills the disk and makes Typesense reject writes). The volume_name filter
# keeps configmap/secret mounts out of scope.
resource "google_monitoring_alert_policy" "typesense_workload_volume" {
  for_each = local.typesense_workload_volume_utilization

  project      = local.typesense_project
  display_name = "Typesense volume utilization ${each.value.severity} ${each.value.threshold * 100}% (cluster=${each.value.cluster_name}, namespace=${each.value.namespace}, volume=${each.value.volume_name}, app=${each.value.app})"
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = true

  conditions {
    display_name = "Typesense pod volume utilization > ${each.value.threshold * 100}%"

    condition_threshold {
      filter = join("\n", compact([
        "resource.type=\"k8s_pod\"",
        "AND resource.labels.project_id=\"${local.typesense_project}\"",
        "AND resource.labels.cluster_name=\"${each.value.cluster_name}\"",
        "AND resource.labels.namespace_name=\"${each.value.namespace}\"",
        "AND metric.type=\"kubernetes.io/pod/volume/utilization\"",
        "AND metric.labels.volume_name=\"${each.value.volume_name}\"",
        each.value.controller_name != null ? "AND metadata.system_labels.top_level_controller_name=\"${each.value.controller_name}\"" : "",
      ]))

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "${each.value.duration_seconds}s"

      aggregations {
        alignment_period   = "${each.value.alignment_period_seconds}s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  dynamic "documentation" {
    for_each = var.typesense.alert_documentation != null ? [var.typesense.alert_documentation] : []

    content {
      content   = documentation.value
      mime_type = "text/markdown"
    }
  }

  notification_channels = each.value.notification_channels

  alert_strategy {
    auto_close           = "${each.value.auto_close_seconds}s"
    notification_prompts = each.value.notification_prompts
  }
}

# Alert: Typesense Replica Availability
# PromQL count of running Typesense pods (konnectivity pattern). CRITICAL
# below raft quorum floor(n/2)+1, WARNING below expected_replicas (skipped
# when it would duplicate the CRITICAL policy). container_uptime counts
# running containers, not ready ones: readiness regressions are covered by
# the uptime check content matcher, this alert covers absence and crash-loops.
resource "google_monitoring_alert_policy" "typesense_workload_replicas" {
  for_each = local.typesense_workload_replicas

  project      = local.typesense_project
  display_name = "Typesense running pods < ${each.value.min_count} (${each.value.reason}) ${each.value.severity} (cluster=${each.value.cluster_name}, namespace=${each.value.namespace}, app=${each.value.app})"
  combiner     = "OR"
  severity     = each.value.severity
  enabled      = true

  conditions {
    display_name = "Typesense running pod count < ${each.value.min_count}"

    condition_prometheus_query_language {
      query = <<-PROMQL
        (
          count(
            max by (pod_name) (
              kubernetes_io:container_uptime{${join(", ", compact([
      "monitored_resource=\"k8s_container\"",
      "project_id=\"${local.typesense_project}\"",
      "cluster_name=\"${each.value.cluster_name}\"",
      "namespace_name=\"${each.value.namespace}\"",
      "container_name=\"${each.value.container_name}\"",
      each.value.controller_name != null ? "metadata_system_top_level_controller_name=\"${each.value.controller_name}\"" : "",
]))}}
            )
          )
          or on() vector(0)
        ) < ${each.value.min_count}
      PROMQL

duration = "${each.value.duration_seconds}s"
}
}

dynamic "documentation" {
  for_each = var.typesense.alert_documentation != null ? [var.typesense.alert_documentation] : []

  content {
    content   = documentation.value
    mime_type = "text/markdown"
  }
}

notification_channels = each.value.notification_channels

alert_strategy {
  auto_close           = "${each.value.auto_close_seconds}s"
  notification_prompts = each.value.notification_prompts
}
}
