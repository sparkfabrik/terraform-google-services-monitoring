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

  # Count the per-node k8s_node series across all pools of the cluster. Guarded
  # on a non-empty cluster_name so the local never interpolates a null when the
  # alert is disabled (locals evaluate regardless of the resource count).
  gke_node_count_filter = local.gke_node_count_cluster_name == "" ? "" : join("\n", [
    "resource.type = \"k8s_node\"",
    "AND resource.labels.project_id = \"${local.gke_node_count_project}\"",
    "AND resource.labels.cluster_name = \"${local.gke_node_count_cluster_name}\"",
    "AND metric.type = \"kubernetes.io/node/cpu/allocatable_cores\"",
  ])
}

# GKE total node count alert. Counts the per-node k8s_node series (REDUCE_COUNT),
# so the evaluated value equals the number of nodes rather than a per-node metric.
resource "google_monitoring_alert_policy" "gke_node_count" {
  count = var.gke_node_count.enabled && var.gke_node_count.cluster_name != null && var.gke_node_count.cluster_name != "" ? 1 : 0

  project      = local.gke_node_count_project
  display_name = "GKE total node count sustained high (cluster=${var.gke_node_count.cluster_name})"
  combiner     = "OR"
  severity     = var.gke_node_count.severity
  user_labels  = var.gke_node_count.user_labels

  conditions {
    display_name = "Total GKE node count exceeds ${var.gke_node_count.threshold}"

    condition_threshold {
      filter          = local.gke_node_count_filter
      comparison      = "COMPARISON_GT"
      threshold_value = var.gke_node_count.threshold
      duration        = var.gke_node_count.duration

      # REDUCE_COUNT tallies the k8s_node series present in each aligned window,
      # so alignment_period must stay close to the metric's 60s sample interval.
      # A long window keeps a terminated node's series in range and overcounts on
      # pools with node churn (spot/preemptible), where the count would exceed
      # the live node count.
      aggregations {
        alignment_period     = var.gke_node_count.alignment_period
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_COUNT"
      }
    }
  }

  documentation {
    content   = "The GKE cluster '${var.gke_node_count.cluster_name}' has had more than ${var.gke_node_count.threshold} nodes for longer than ${var.gke_node_count.duration}. This may indicate unexpected autoscaling that impacts costs. Review node pool sizing and workload demand."
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
