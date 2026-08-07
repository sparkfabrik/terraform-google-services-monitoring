locals {
  gke_node_count_project = (
    var.gke_node_count.project_id != null
    ? var.gke_node_count.project_id
    : var.project_id
  )

  gke_node_count_notification_channels = (
    var.gke_node_count.notification_enabled
    ? (
      length(var.gke_node_count.notification_channels) > 0
      ? var.gke_node_count.notification_channels
      : var.notification_channels
    )
    : []
  )

  gke_node_count_cluster_name = var.gke_node_count.cluster_name != null ? var.gke_node_count.cluster_name : ""

  # The k8s_node system metadata label carrying the node pool name.
  gke_node_count_nodepool_label = "metadata.system_labels.\"cloud.google.com/gke-nodepool\""

  # Per-pool mode: a non-empty node_pool_thresholds map turns the alert into one
  # condition per named pool, each with its own threshold.
  gke_node_count_per_pool = length(var.gke_node_count.node_pool_thresholds) > 0

  # Display suffix reflecting the counting mode.
  gke_node_count_mode_suffix = (
    local.gke_node_count_per_pool
    ? ", per node pool"
    : var.gke_node_count.node_pool_name != null ? ", pool=${var.gke_node_count.node_pool_name}" : ""
  )

  # Normalized condition list: one entry per policy condition. Per-pool mode
  # yields one entry per map key (each scoped to its pool with its own
  # threshold); otherwise a single entry counts the cluster total (optionally
  # scoped to node_pool_name). Guarded on a non-empty cluster_name so the
  # entries never carry a null pool clause when the alert is disabled (locals
  # evaluate regardless of the resource count).
  gke_node_count_conditions = local.gke_node_count_cluster_name == "" ? {} : (
    local.gke_node_count_per_pool
    ? { for pool, threshold in var.gke_node_count.node_pool_thresholds : pool => {
      pool      = pool
      threshold = threshold
    } }
    : { total = {
      pool      = var.gke_node_count.node_pool_name
      threshold = var.gke_node_count.threshold
    } }
  )
}

# GKE node count alert. Counts the per-node k8s_node series (REDUCE_COUNT), so the
# evaluated value equals the number of nodes rather than a per-node metric. With a
# node_pool_thresholds map, one condition per named pool is emitted, each scoped to
# its pool and compared against its own threshold (the policy fires if any pool is
# over its threshold).
resource "google_monitoring_alert_policy" "gke_node_count" {
  count = var.gke_node_count.enabled && var.gke_node_count.cluster_name != null && var.gke_node_count.cluster_name != "" ? 1 : 0

  project      = local.gke_node_count_project
  display_name = "GKE node count sustained high (cluster=${var.gke_node_count.cluster_name}${local.gke_node_count_mode_suffix})"
  combiner     = "OR"
  severity     = var.gke_node_count.severity
  user_labels  = var.gke_node_count.user_labels

  dynamic "conditions" {
    for_each = local.gke_node_count_conditions
    content {
      display_name = conditions.value.pool != null ? "Node pool '${conditions.value.pool}' node count exceeds ${conditions.value.threshold}" : "Total GKE node count exceeds ${conditions.value.threshold}"

      condition_threshold {
        filter = join("\n", concat([
          "resource.type = \"k8s_node\"",
          "AND resource.labels.cluster_name = \"${local.gke_node_count_cluster_name}\"",
          "AND metric.type = \"kubernetes.io/node/cpu/allocatable_cores\"",
          ], conditions.value.pool != null ? [
          "AND ${local.gke_node_count_nodepool_label} = \"${conditions.value.pool}\""
        ] : []))
        comparison      = "COMPARISON_GT"
        threshold_value = conditions.value.threshold
        duration        = var.gke_node_count.duration

        aggregations {
          alignment_period     = var.gke_node_count.alignment_period
          per_series_aligner   = "ALIGN_MEAN"
          cross_series_reducer = "REDUCE_COUNT"
        }
      }
    }
  }

  documentation {
    content   = "The GKE cluster '${var.gke_node_count.cluster_name}' has had more nodes${local.gke_node_count_per_pool ? " in a monitored node pool" : ""} than the configured threshold for longer than ${var.gke_node_count.duration}. This may indicate unexpected autoscaling that impacts costs. Review node pool sizing and workload demand."
    mime_type = "text/markdown"
  }

  notification_channels = local.gke_node_count_notification_channels

  dynamic "alert_strategy" {
    for_each = var.gke_node_count.auto_close != null ? [1] : []
    content {
      auto_close = var.gke_node_count.auto_close
    }
  }
}
