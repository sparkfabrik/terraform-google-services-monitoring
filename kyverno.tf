locals {
  kyverno_project_id            = var.kyverno.project_id != null ? var.kyverno.project_id : var.project_id
  kyverno_cluster_name          = var.kyverno.cluster_name != null ? trimspace(var.kyverno.cluster_name) : ""
  kyverno_notification_channels = var.kyverno.notification_enabled ? (length(var.kyverno.notification_channels) > 0 ? var.kyverno.notification_channels : var.notification_channels) : []
  kyverno_enabled               = var.kyverno.enabled && local.kyverno_cluster_name != ""

  kyverno_alert_documentation = var.kyverno.alert_documentation != null ? var.kyverno.alert_documentation : "Kyverno produced ERROR logs in namespace ${var.kyverno.namespace} on cluster ${local.kyverno_cluster_name}. See the Kyverno policy dashboard and the kyverno namespace logs."

  # Tier 1 noise classes, matched on jsonPayload.message OR jsonPayload.error.
  # Patterns are plain substrings (no regex metacharacters), joined into one alternation.
  kyverno_noise_regex = try(join("|", var.kyverno.service_errors_check.noise_exclusions), "")

  # Tier 1 — service errors: ERROR logs, excluding the engine logger and the measured noise classes.
  kyverno_tier1_filter = <<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.kyverno_project_id}"
    AND resource.labels.cluster_name="${local.kyverno_cluster_name}"
    AND resource.labels.namespace_name="${var.kyverno.namespace}"
    AND severity=ERROR
    AND NOT jsonPayload.logger=~"^engine"
    %{~if local.kyverno_noise_regex != ""~}
    AND NOT (
      jsonPayload.message=~"(?i)(${local.kyverno_noise_regex})"
      OR jsonPayload.error=~"(?i)(${local.kyverno_noise_regex})"
    )
    %{~endif~}
  EOT

  # Tier 2 — volume catch-all: same source, no exclusions, still excluding the engine logger.
  kyverno_tier2_filter = <<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.kyverno_project_id}"
    AND resource.labels.cluster_name="${local.kyverno_cluster_name}"
    AND resource.labels.namespace_name="${var.kyverno.namespace}"
    AND severity=ERROR
    AND NOT jsonPayload.logger=~"^engine"
  EOT

  # Engine — broken policies: engine-logger ERROR logs, labeled by policy name.
  kyverno_engine_filter = <<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.kyverno_project_id}"
    AND resource.labels.cluster_name="${local.kyverno_cluster_name}"
    AND resource.labels.namespace_name="${var.kyverno.namespace}"
    AND severity=ERROR
    AND jsonPayload.logger=~"^engine"
  EOT
}

# Level 1 — Admission Controller Pod Restarts
# condition_threshold on the system metric kubernetes.io/container/restart_count,
# scoped to kyverno-admission-controller pods. Mirrors typesense_pod_restart
# (ALIGN_DELTA / REDUCE_SUM). A dead or hung controller (liveness probe converts
# "hung" into a restart) raises the restart delta and opens the alert.
resource "google_monitoring_alert_policy" "kyverno_admission_restart" {
  count = local.kyverno_enabled && try(var.kyverno.restart_check.enabled, false) ? 1 : 0

  project      = local.kyverno_project_id
  display_name = "Kyverno admission controller restarts (cluster=${local.kyverno_cluster_name}, namespace=${var.kyverno.namespace})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Admission controller restart count > ${var.kyverno.restart_check.threshold}"

    condition_threshold {
      filter = <<-EOT
        resource.type="k8s_container"
        AND resource.labels.project_id="${local.kyverno_project_id}"
        AND resource.labels.cluster_name="${local.kyverno_cluster_name}"
        AND resource.labels.namespace_name="${var.kyverno.namespace}"
        AND metric.type="kubernetes.io/container/restart_count"
        AND resource.labels.pod_name=monitoring.regex.full_match("kyverno-admission-controller-.*")
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = var.kyverno.restart_check.threshold
      duration        = "${var.kyverno.restart_check.duration}s"

      aggregations {
        alignment_period     = "${var.kyverno.restart_check.alignment_period}s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "resource.label.pod_name",
        ]
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = local.kyverno_alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.kyverno_notification_channels

  alert_strategy {
    auto_close           = "${var.kyverno.restart_check.auto_close_seconds}s"
    notification_prompts = var.kyverno.restart_check.notification_prompts
  }
}

# Tier 1 metric — service errors
# Log-based counter over ERROR logs in the kyverno namespace, excluding the engine
# logger and the 12 measured noise classes (matched on message OR error). Baseline 0/7d.
resource "google_logging_metric" "kyverno_service_errors" {
  count = local.kyverno_enabled && try(var.kyverno.service_errors_check.enabled, false) ? 1 : 0

  project = local.kyverno_project_id
  name    = "kyverno_service_errors_${local.kyverno_cluster_name}"
  filter  = local.kyverno_tier1_filter

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Kyverno service ERROR count (cluster=${local.kyverno_cluster_name})"
  }
}

# Tier 1 alert — service errors > threshold in the alignment window.
resource "google_monitoring_alert_policy" "kyverno_service_errors" {
  count = local.kyverno_enabled && try(var.kyverno.service_errors_check.enabled, false) ? 1 : 0

  project      = local.kyverno_project_id
  display_name = "Kyverno service errors — tier 1 (cluster=${local.kyverno_cluster_name}, namespace=${var.kyverno.namespace})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Service ERROR count > ${var.kyverno.service_errors_check.threshold}"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.kyverno_service_errors[0].name}\" AND resource.type=\"k8s_container\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.kyverno.service_errors_check.threshold
      duration        = "${var.kyverno.service_errors_check.duration}s"

      aggregations {
        alignment_period     = "${var.kyverno.service_errors_check.alignment_period}s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = local.kyverno_alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.kyverno_notification_channels

  alert_strategy {
    auto_close = "${var.kyverno.service_errors_check.auto_close_seconds}s"
  }

  depends_on = [google_logging_metric.kyverno_service_errors]
}

# Tier 2 metric — volume catch-all
# Same source as tier 1 but with no exclusions, so a flood of any class (even a
# normally-excluded benign one) is counted. Guards against the exclusion list
# hiding a sustained incident.
resource "google_logging_metric" "kyverno_error_volume" {
  count = local.kyverno_enabled && try(var.kyverno.volume_check.enabled, false) ? 1 : 0

  project = local.kyverno_project_id
  name    = "kyverno_error_volume_${local.kyverno_cluster_name}"
  filter  = local.kyverno_tier2_filter

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Kyverno ERROR volume (cluster=${local.kyverno_cluster_name})"
  }
}

# Tier 2 alert — error volume sustained above threshold per alignment window.
resource "google_monitoring_alert_policy" "kyverno_error_volume" {
  count = local.kyverno_enabled && try(var.kyverno.volume_check.enabled, false) ? 1 : 0

  project      = local.kyverno_project_id
  display_name = "Kyverno error volume — tier 2 catch-all (cluster=${local.kyverno_cluster_name}, namespace=${var.kyverno.namespace})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "ERROR volume > ${var.kyverno.volume_check.threshold}/min sustained"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.kyverno_error_volume[0].name}\" AND resource.type=\"k8s_container\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.kyverno.volume_check.threshold
      duration        = "${var.kyverno.volume_check.duration}s"

      aggregations {
        alignment_period     = "${var.kyverno.volume_check.alignment_period}s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = local.kyverno_alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.kyverno_notification_channels

  alert_strategy {
    auto_close = "${var.kyverno.volume_check.auto_close_seconds}s"
  }

  depends_on = [google_logging_metric.kyverno_error_volume]
}

# Engine metric — broken policies
# Log-based counter over engine-logger ERROR logs, labeled by the structured field
# jsonPayload."policy.name" so each broken policy is a distinct time series.
resource "google_logging_metric" "kyverno_engine_errors" {
  count = local.kyverno_enabled && try(var.kyverno.engine_check.enabled, false) ? 1 : 0

  project = local.kyverno_project_id
  name    = "kyverno_engine_errors_${local.kyverno_cluster_name}"
  filter  = local.kyverno_engine_filter

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Kyverno engine ERROR count (cluster=${local.kyverno_cluster_name})"

    labels {
      key         = "policy"
      value_type  = "STRING"
      description = "Kyverno policy name extracted from the engine error log (jsonPayload.\"policy.name\")"
    }
  }

  label_extractors = {
    policy = "EXTRACT(jsonPayload.\"policy.name\")"
  }
}

# Engine alert — broken policies, one incident per policy.
# Groups by the policy label so a newly-broken policy is not masked by one already
# firing. A metric-threshold alert notifies once when the incident opens and stays
# open while the condition holds (no per-evaluation loop), so a persistently-broken
# policy such as zambon's tenant-require-resource-limits notifies a single time.
# (notification_rate_limit is rejected by the API on metric-threshold alerts — it is
# allowed only on log-based condition_matched_log policies.)
resource "google_monitoring_alert_policy" "kyverno_engine_errors" {
  count = local.kyverno_enabled && try(var.kyverno.engine_check.enabled, false) ? 1 : 0

  project      = local.kyverno_project_id
  display_name = "Kyverno broken policies — engine errors (cluster=${local.kyverno_cluster_name}, namespace=${var.kyverno.namespace})"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Engine ERROR count > ${var.kyverno.engine_check.threshold} per policy"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.kyverno_engine_errors[0].name}\" AND resource.type=\"k8s_container\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.kyverno.engine_check.threshold
      duration        = "${var.kyverno.engine_check.duration}s"

      aggregations {
        alignment_period     = "${var.kyverno.engine_check.alignment_period}s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "metric.label.policy",
        ]
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = local.kyverno_alert_documentation
    mime_type = "text/markdown"
  }

  notification_channels = local.kyverno_notification_channels

  alert_strategy {
    auto_close = "${var.kyverno.engine_check.auto_close_seconds}s"
  }

  depends_on = [google_logging_metric.kyverno_engine_errors]
}

# Policy review dashboard
# First google_monitoring_dashboard in this module. Two sections:
#   A — violated policies, from PolicyViolation Kubernetes events (Log Analytics SQL).
#   B — error-producing policies, from engine ERROR logs (Log Analytics SQL) plus an
#       engine-error rate chart on the kyverno_engine_errors log-based metric.
# Requires Log Analytics on the project's _Default bucket (SQL widget prerequisite).
locals {
  kyverno_dashboard_enabled = local.kyverno_enabled && try(var.kyverno.dashboard.enabled, false)

  # Log Analytics view backing the SQL widgets (the project's _Default bucket).
  kyverno_log_view = "`${local.kyverno_project_id}.global._Default._AllLogs`"

  kyverno_engine_metric_name = "kyverno_engine_errors_${local.kyverno_cluster_name}"

  # Distinct violating-resource key, extracted from the PolicyViolation event message.
  # Kyverno's policy-side event message starts with "<Kind> <namespace>/<name>: ..."
  # (cluster-scoped resources omit the namespace). The leading token up to the first
  # colon identifies the resource; the trailing numeric suffix of CronJob-spawned Jobs
  # is normalized away so re-runs collapse to one resource.
  # NOTE: this regex assumes the standard Kyverno event message layout — validate and
  # tune against real data on zambon (TEST-PLAN 0.10, expected ~270 distinct resources).
  kyverno_violating_resource_expr = "REGEXP_REPLACE(REGEXP_EXTRACT(JSON_VALUE(json_payload.message), r'^([^:]+):'), r'-[0-9]+$', '')"

  # Common WHERE for Section A (PolicyViolation events, policy-side only to dedup).
  kyverno_section_a_where = <<-EOT
    log_name LIKE '%/logs/events'
        AND JSON_VALUE(json_payload.reason) = 'PolicyViolation'
        AND REGEXP_CONTAINS(JSON_VALUE(json_payload.involvedObject.kind), r'^(Cluster)?Policy$')
  EOT

  # Common WHERE for Section B (engine-logger ERROR logs in the kyverno namespace).
  kyverno_section_b_where = <<-EOT
    resource.type = 'k8s_container'
        AND JSON_VALUE(resource.labels.cluster_name) = '${local.kyverno_cluster_name}'
        AND JSON_VALUE(resource.labels.namespace_name) = '${var.kyverno.namespace}'
        AND severity = 'ERROR'
        AND REGEXP_CONTAINS(JSON_VALUE(json_payload.logger), r'^engine')
  EOT

  # Section A widgets.
  kyverno_sql_a_total = <<-EOT
    SELECT
      COUNT(DISTINCT ${local.kyverno_violating_resource_expr}) AS distinct_violating_resources
    FROM ${local.kyverno_log_view}
    WHERE ${local.kyverno_section_a_where}
      AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${var.kyverno.dashboard.window_hours} HOUR)
  EOT

  kyverno_sql_a_by_policy = <<-EOT
    SELECT
      JSON_VALUE(json_payload.involvedObject.name) AS policy,
      COUNT(DISTINCT ${local.kyverno_violating_resource_expr}) AS distinct_violating_resources
    FROM ${local.kyverno_log_view}
    WHERE ${local.kyverno_section_a_where}
      AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${var.kyverno.dashboard.window_hours} HOUR)
    GROUP BY policy
    ORDER BY distinct_violating_resources DESC
  EOT

  kyverno_sql_a_by_namespace = <<-EOT
    SELECT
      COALESCE(REGEXP_EXTRACT(JSON_VALUE(json_payload.message), r'^\S+ ([^/]+)/'), '(cluster-scoped)') AS namespace,
      COUNT(DISTINCT ${local.kyverno_violating_resource_expr}) AS distinct_violating_resources
    FROM ${local.kyverno_log_view}
    WHERE ${local.kyverno_section_a_where}
      AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${var.kyverno.dashboard.window_hours} HOUR)
    GROUP BY namespace
    ORDER BY distinct_violating_resources DESC
  EOT

  kyverno_sql_a_trend = <<-EOT
    SELECT
      TIMESTAMP_TRUNC(timestamp, DAY) AS day,
      COUNT(DISTINCT ${local.kyverno_violating_resource_expr}) AS distinct_violating_resources
    FROM ${local.kyverno_log_view}
    WHERE ${local.kyverno_section_a_where}
      AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    GROUP BY day
    ORDER BY day
  EOT

  # Section B widgets (engine errors; per-policy split on the structured field).
  kyverno_sql_b_count = <<-EOT
    SELECT
      COUNT(DISTINCT JSON_VALUE(json_payload['policy.name'])) AS policies_in_error
    FROM ${local.kyverno_log_view}
    WHERE ${local.kyverno_section_b_where}
      AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${var.kyverno.dashboard.window_hours} HOUR)
  EOT

  kyverno_sql_b_by_policy = <<-EOT
    SELECT
      JSON_VALUE(json_payload['policy.name']) AS policy,
      COUNT(*) AS error_count
    FROM ${local.kyverno_log_view}
    WHERE ${local.kyverno_section_b_where}
      AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL ${var.kyverno.dashboard.window_hours} HOUR)
    GROUP BY policy
    ORDER BY error_count DESC
  EOT

  kyverno_dashboard_json = jsonencode({
    displayName = "Kyverno policy review (cluster=${local.kyverno_cluster_name})"
    mosaicLayout = {
      columns = 48
      tiles = [
        {
          xPos = 0, yPos = 0, width = 48, height = 2
          widget = {
            title = "Section A — Violated policies"
            text = {
              content = "Distinct violating resources from `PolicyViolation` events (policy-side, deduped), current state over ${var.kyverno.dashboard.window_hours}h. Raw event counts are meaningless (resources × scans/day) — distinct-resource counting only."
              format  = "MARKDOWN"
            }
          }
        },
        {
          xPos = 0, yPos = 2, width = 12, height = 10
          widget = {
            title = "Distinct violating resources (current state)"
            timeSeriesTable = {
              dataSets            = [{ timeSeriesQuery = { opsAnalyticsQuery = { sql = local.kyverno_sql_a_total } } }]
              metricVisualization = "NUMBER"
            }
          }
        },
        {
          xPos = 12, yPos = 2, width = 18, height = 10
          widget = {
            title = "Distinct violating resources per policy"
            timeSeriesTable = {
              dataSets            = [{ timeSeriesQuery = { opsAnalyticsQuery = { sql = local.kyverno_sql_a_by_policy } } }]
              metricVisualization = "NUMBER"
            }
          }
        },
        {
          xPos = 30, yPos = 2, width = 18, height = 10
          widget = {
            title = "Distinct violating resources per namespace"
            timeSeriesTable = {
              dataSets            = [{ timeSeriesQuery = { opsAnalyticsQuery = { sql = local.kyverno_sql_a_by_namespace } } }]
              metricVisualization = "NUMBER"
            }
          }
        },
        {
          xPos = 0, yPos = 12, width = 48, height = 12
          widget = {
            title = "Distinct violating resources — daily trend (30d)"
            xyChart = {
              dataSets = [{
                plotType        = "LINE"
                targetAxis      = "Y1"
                timeSeriesQuery = { opsAnalyticsQuery = { sql = local.kyverno_sql_a_trend } }
              }]
              yAxis = { label = "distinct resources", scale = "LINEAR" }
            }
          }
        },
        {
          xPos = 0, yPos = 24, width = 48, height = 2
          widget = {
            title = "Section B — Error-producing policies"
            text = {
              content = "Policies emitting engine ERROR logs (`severity=ERROR AND jsonPayload.logger=~\"^engine\"`), split by the structured field `jsonPayload.\"policy.name\"`."
              format  = "MARKDOWN"
            }
          }
        },
        {
          xPos = 0, yPos = 26, width = 12, height = 10
          widget = {
            title = "Policies currently in error"
            timeSeriesTable = {
              dataSets            = [{ timeSeriesQuery = { opsAnalyticsQuery = { sql = local.kyverno_sql_b_count } } }]
              metricVisualization = "NUMBER"
            }
          }
        },
        {
          xPos = 12, yPos = 26, width = 18, height = 10
          widget = {
            title = "Engine error count per policy"
            timeSeriesTable = {
              dataSets            = [{ timeSeriesQuery = { opsAnalyticsQuery = { sql = local.kyverno_sql_b_by_policy } } }]
              metricVisualization = "NUMBER"
            }
          }
        },
        {
          xPos = 30, yPos = 26, width = 18, height = 10
          widget = {
            title = "Engine-error rate per policy"
            xyChart = {
              dataSets = [{
                plotType   = "LINE"
                targetAxis = "Y1"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${local.kyverno_engine_metric_name}\" AND resource.type=\"k8s_container\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.policy"]
                    }
                  }
                }
              }]
              yAxis = { label = "errors", scale = "LINEAR" }
            }
          }
        },
      ]
    }
  })
}

resource "google_monitoring_dashboard" "kyverno_policy_review" {
  count = local.kyverno_dashboard_enabled ? 1 : 0

  project        = local.kyverno_project_id
  dashboard_json = local.kyverno_dashboard_json
}
