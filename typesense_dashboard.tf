# Typesense per-app Cloud Monitoring dashboard.
#
# One google_monitoring_dashboard per app whose 'dashboard' block is enabled,
# assembled strictly from data the module already wires: free kubernetes.io
# system metrics, the flood log-based metric, a dedicated error-log counter
# metric and the uptime check. Sections render only when the backing check is
# configured; remaining tiles reflow densely.
#
# Drift-safe JSON authoring (the Cloud Monitoring API normalizes
# dashboard_json on write, so any value it strips becomes a perpetual plan
# diff): xPos/yPos keys are attached only when non-zero, no empty
# arrays/objects/strings, no nulls, enums uppercase and never zero-valued,
# no blankView, thresholds are integers (float32-exact).

locals {
  typesense_dashboard_apps = var.typesense.enabled ? {
    for app_name, config in var.typesense.apps :
    app_name => config
    if config.dashboard != null && try(config.dashboard.enabled, false)
  } : {}

  # Apps whose dashboard renders the error-log rate chart and therefore need
  # the backing counter metric.
  typesense_dashboard_error_log_apps = {
    for app_name, config in local.typesense_dashboard_apps :
    app_name => config
    if config.log_check != null && try(config.log_check.enabled, false)
  }

  typesense_dashboard_checks = {
    for app_name, config in local.typesense_dashboard_apps :
    app_name => {
      uptime    = config.uptime_check != null && try(config.uptime_check.enabled, false)
      container = config.container_check != null && try(config.container_check.enabled, false)
      log       = config.log_check != null && try(config.log_check.enabled, false)
      flood     = config.flood_check != null && try(config.flood_check.enabled, false)
      workload  = config.workload_check != null && try(config.workload_check.enabled, false)
    }
  }

  # Default title contract: "Typesense vitals — <app> (cluster=..., namespace=...)";
  # segments whose value is unset are omitted, display_name overrides everything.
  typesense_dashboard_title_segments = {
    for app_name, config in local.typesense_dashboard_apps :
    app_name => compact([
      local.typesense_cluster_names[app_name] != null ? "cluster=${local.typesense_cluster_names[app_name]}" : "",
      local.typesense_namespaces[app_name] != null ? "namespace=${local.typesense_namespaces[app_name]}" : "",
    ])
  }

  typesense_dashboard_titles = {
    for app_name, config in local.typesense_dashboard_apps :
    app_name => config.dashboard.display_name != null ? config.dashboard.display_name : (
      length(local.typesense_dashboard_title_segments[app_name]) > 0
      ? "Typesense vitals — ${app_name} (${join(", ", local.typesense_dashboard_title_segments[app_name])})"
      : "Typesense vitals — ${app_name}"
    )
  }

  # Per-app values shared by the widget filters. Kubernetes-only fields fall
  # back to harmless placeholders for apps without Kubernetes checks (their
  # widgets are never rendered; the fallbacks only keep evaluation total).
  typesense_dashboard_selectors = {
    for app_name, config in local.typesense_dashboard_apps :
    app_name => {
      container_name  = try(config.workload_check.container_name, "typesense")
      volume_name     = try(config.workload_check.volume_name, "data")
      controller_name = try(config.workload_check.controller_name, null)
      expected        = try(config.workload_check.expected_replicas, 0)
      quorum          = try(floor(config.workload_check.expected_replicas / 2) + 1, 0)
      uptime_check_id = try(module.typesense_uptime_checks[app_name].uptime_check_id, "")

      container_filter = join(" AND ", [
        "resource.type=\"k8s_container\"",
        "resource.labels.project_id=\"${local.typesense_project}\"",
        "resource.labels.cluster_name=\"${try(coalesce(local.typesense_cluster_names[app_name]), "")}\"",
        "resource.labels.namespace_name=\"${try(coalesce(local.typesense_namespaces[app_name]), "")}\"",
      ])
      pod_filter = join(" AND ", [
        "resource.type=\"k8s_pod\"",
        "resource.labels.project_id=\"${local.typesense_project}\"",
        "resource.labels.cluster_name=\"${try(coalesce(local.typesense_cluster_names[app_name]), "")}\"",
        "resource.labels.namespace_name=\"${try(coalesce(local.typesense_namespaces[app_name]), "")}\"",
      ])
    }
  }

  typesense_dashboard_widgets = {
    for app_name, s in local.typesense_dashboard_selectors :
    app_name => {
      replica_scorecard = {
        title = "Running replicas"
        scorecard = {
          timeSeriesQuery = {
            prometheusQuery = "count(max by (pod_name) (kubernetes_io:container_uptime{${join(", ", compact([
              "monitored_resource=\"k8s_container\"",
              "project_id=\"${local.typesense_project}\"",
              "cluster_name=\"${try(coalesce(local.typesense_cluster_names[app_name]), "")}\"",
              "namespace_name=\"${try(coalesce(local.typesense_namespaces[app_name]), "")}\"",
              "container_name=\"${s.container_name}\"",
              s.controller_name != null ? "metadata_system_top_level_controller_name=\"${s.controller_name}\"" : "",
            ]))}})) or on() vector(0)"
          }
          thresholds = concat(
            [{ value = s.quorum, color = "RED", direction = "BELOW" }],
            s.expected > s.quorum ? [{ value = s.expected, color = "YELLOW", direction = "BELOW" }] : []
          )
        }
      }

      uptime_scorecard = {
        title = "Uptime check pass ratio"
        scorecard = {
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${s.uptime_check_id}\" AND resource.type=\"uptime_url\""
              aggregation = {
                alignmentPeriod    = "1200s"
                perSeriesAligner   = "ALIGN_FRACTION_TRUE"
                crossSeriesReducer = "REDUCE_MEAN"
              }
            }
          }
          thresholds = [{ value = 1, color = "RED", direction = "BELOW" }]
        }
      }

      memory_chart = {
        title = "Memory limit utilization per pod"
        xyChart = {
          dataSets = [{
            plotType   = "LINE"
            targetAxis = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "${s.container_filter} AND resource.labels.container_name=\"${s.container_name}\" AND metric.type=\"kubernetes.io/container/memory/limit_utilization\" AND metric.labels.memory_type=\"non-evictable\""
                aggregation = {
                  alignmentPeriod    = "300s"
                  perSeriesAligner   = "ALIGN_MEAN"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["resource.label.pod_name"]
                }
              }
            }
          }]
          yAxis = { label = "ratio", scale = "LINEAR" }
        }
      }

      cpu_chart = {
        title = "CPU limit utilization per pod"
        xyChart = {
          dataSets = [{
            plotType   = "LINE"
            targetAxis = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "${s.container_filter} AND resource.labels.container_name=\"${s.container_name}\" AND metric.type=\"kubernetes.io/container/cpu/limit_utilization\""
                aggregation = {
                  alignmentPeriod    = "300s"
                  perSeriesAligner   = "ALIGN_MEAN"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["resource.label.pod_name"]
                }
              }
            }
          }]
          yAxis = { label = "ratio", scale = "LINEAR" }
        }
      }

      volume_chart = {
        title = "PVC volume utilization per pod"
        xyChart = {
          dataSets = [{
            plotType   = "LINE"
            targetAxis = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "${s.pod_filter} AND metric.type=\"kubernetes.io/pod/volume/utilization\" AND metric.labels.volume_name=\"${s.volume_name}\""
                aggregation = {
                  alignmentPeriod    = "300s"
                  perSeriesAligner   = "ALIGN_MEAN"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["resource.label.pod_name"]
                }
              }
            }
          }]
          yAxis = { label = "ratio", scale = "LINEAR" }
        }
      }

      restart_chart = {
        title = "Container restarts per pod"
        xyChart = {
          dataSets = [{
            plotType   = "LINE"
            targetAxis = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "${s.container_filter} AND metric.type=\"kubernetes.io/container/restart_count\""
                aggregation = {
                  alignmentPeriod    = "300s"
                  perSeriesAligner   = "ALIGN_DELTA"
                  crossSeriesReducer = "REDUCE_SUM"
                  groupByFields      = ["resource.label.pod_name"]
                }
              }
            }
          }]
          yAxis = { label = "restarts", scale = "LINEAR" }
        }
      }

      flood_chart = {
        title = "Log volume per pod"
        xyChart = {
          dataSets = [{
            plotType   = "LINE"
            targetAxis = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "metric.type=\"logging.googleapis.com/user/typesense_log_volume_${app_name}\" AND resource.type=\"k8s_container\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_RATE"
                  crossSeriesReducer = "REDUCE_SUM"
                  groupByFields      = ["resource.label.pod_name"]
                }
              }
            }
          }]
          yAxis = { label = "entries/s", scale = "LINEAR" }
        }
      }

      error_log_chart = {
        title = "Error-log rate per pod"
        xyChart = {
          dataSets = [{
            plotType   = "LINE"
            targetAxis = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "metric.type=\"logging.googleapis.com/user/typesense_error_logs_${app_name}\" AND resource.type=\"k8s_container\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_RATE"
                  crossSeriesReducer = "REDUCE_SUM"
                  groupByFields      = ["resource.label.pod_name"]
                }
              }
            }
          }]
          yAxis = { label = "entries/s", scale = "LINEAR" }
        }
      }

      latency_chart = {
        title = "Uptime check latency"
        xyChart = {
          dataSets = [{
            plotType   = "LINE"
            targetAxis = "Y1"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "metric.type=\"monitoring.googleapis.com/uptime_check/request_latency\" AND metric.labels.check_id=\"${s.uptime_check_id}\" AND resource.type=\"uptime_url\""
                aggregation = {
                  alignmentPeriod    = "900s"
                  perSeriesAligner   = "ALIGN_MEAN"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["metric.label.checker_location"]
                }
              }
            }
          }]
          yAxis = { label = "ms", scale = "LINEAR" }
        }
      }
    }
  }

  # Rows of tiles (48-column mosaic, two 24-wide tiles per row). Rows whose
  # backing checks are absent come out empty and are dropped, so present
  # sections stack densely. The 'for ... if' construction keeps every row a
  # tuple: no type unification, no null attributes leaking into the JSON.
  typesense_dashboard_rows = {
    for app_name, w in local.typesense_dashboard_widgets :
    app_name => [
      for row in [
        concat(
          [for widget in [w.replica_scorecard] : { width = 24, height = 8, widget = widget } if local.typesense_dashboard_checks[app_name].workload],
          [for widget in [w.uptime_scorecard] : { width = 24, height = 8, widget = widget } if local.typesense_dashboard_checks[app_name].uptime],
        ),
        [for widget in [w.memory_chart, w.cpu_chart] : { width = 24, height = 16, widget = widget } if local.typesense_dashboard_checks[app_name].workload],
        concat(
          [for widget in [w.volume_chart] : { width = 24, height = 16, widget = widget } if local.typesense_dashboard_checks[app_name].workload],
          [for widget in [w.restart_chart] : { width = 24, height = 16, widget = widget } if local.typesense_dashboard_checks[app_name].container || local.typesense_dashboard_checks[app_name].workload],
        ),
        concat(
          [for widget in [w.flood_chart] : { width = 24, height = 16, widget = widget } if local.typesense_dashboard_checks[app_name].flood],
          [for widget in [w.error_log_chart] : { width = 24, height = 16, widget = widget } if local.typesense_dashboard_checks[app_name].log],
        ),
        [for widget in [w.latency_chart] : { width = 24, height = 16, widget = widget } if local.typesense_dashboard_checks[app_name].uptime],
      ] : row if length(row) > 0
    ]
  }

  typesense_dashboard_row_heights = {
    for app_name, rows in local.typesense_dashboard_rows :
    app_name => [for row in rows : max([for tile in row : tile.height]...)]
  }

  # Flatten rows into positioned tiles. xPos/yPos are attached via merge()
  # only when non-zero: the API strips zero positions, so emitting them would
  # cause a perpetual plan diff (the origin tile carries neither key).
  typesense_dashboard_tiles = {
    for app_name, rows in local.typesense_dashboard_rows :
    app_name => flatten([
      for row_index, row in rows : [
        for tile_index, tile in row : merge(
          { width = tile.width, height = tile.height, widget = tile.widget },
          { for k, v in { xPos = tile_index == 0 ? 0 : sum(slice([for t in row : t.width], 0, tile_index)) } : k => v if v > 0 },
          { for k, v in { yPos = row_index == 0 ? 0 : sum(slice(local.typesense_dashboard_row_heights[app_name], 0, row_index)) } : k => v if v > 0 },
        )
      ]
    ])
  }
}

# Metric: Typesense Error Logs
# User-defined log-based counter metric counting ERROR-and-above log entries
# from a given namespace (flood-metric filter pattern). Created only for apps
# with both log_check and the dashboard enabled; feeds the dashboard's
# error-log rate chart. Generated series volume is ~0.33 MiB/month per app.
resource "google_logging_metric" "typesense_error_logs" {
  for_each = local.typesense_dashboard_error_log_apps

  project = local.typesense_project
  name    = "typesense_error_logs_${each.key}"

  filter = <<-EOT
    resource.type="k8s_container"
    AND resource.labels.project_id="${local.typesense_project}"
    AND resource.labels.cluster_name="${local.typesense_cluster_names[each.key]}"
    AND resource.labels.namespace_name="${local.typesense_namespaces[each.key]}"
    AND severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Typesense error log count (cluster=${local.typesense_cluster_names[each.key]}, namespace=${local.typesense_namespaces[each.key]}, app=${each.key})"
  }
}

# Dashboard: Typesense app vitals
# One dashboard per enabled app. displayName is not the resource identity:
# title changes (including display_name overrides) are in-place updates.
resource "google_monitoring_dashboard" "typesense_app" {
  for_each = local.typesense_dashboard_apps

  project = local.typesense_project
  dashboard_json = jsonencode({
    displayName = local.typesense_dashboard_titles[each.key]
    mosaicLayout = {
      columns = 48
      tiles   = local.typesense_dashboard_tiles[each.key]
    }
  })
}
