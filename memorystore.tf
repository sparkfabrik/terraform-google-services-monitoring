# ----------------------
# Memorystore
# ----------------------
locals {
  memorystore_project = var.memorystore.project_id != null ? var.memorystore.project_id : var.project_id

  memorystore_notification_channels = var.memorystore.notification_enabled ? (length(var.memorystore.notification_channels) > 0 ? var.memorystore.notification_channels : var.notification_channels) : []

  memorystore_instance_cpu_utilization = {
    for item in flatten(
      [
        for instance, instance_config in var.memorystore.instances : [
          for cpu_utilization in instance_config.cpu_utilization :
          merge(
            {
              "instance" : instance,
            },
            cpu_utilization
          )
        ]
      ]
    ) : "${item.instance}--${item.severity}--${item.threshold}" => item
  }

  memorystore_cluster_cpu_utilization = {
    for item in flatten(
      [
        for cluster, cluster_config in var.memorystore.clusters : [
          for cpu_utilization in cluster_config.cpu_utilization :
          merge(
            {
              "cluster" : cluster,
            },
            cpu_utilization
          )
        ]
      ]
    ) : "${item.cluster}--${item.severity}--${item.threshold}" => item
  }
}

# ----------------------
# Memorystore Redis Instance CPU Utilization
# ----------------------
resource "google_monitoring_alert_policy" "memorystore_instance_cpu" {
  for_each = local.memorystore_instance_cpu_utilization

  project      = local.memorystore_project
  display_name = "${local.memorystore_project} ${each.value.instance} - Instance CPU utilization ${each.value.severity} ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter = <<-EOT
        resource.type="redis.googleapis.com/Instance"
        AND resource.labels.project_id="${local.memorystore_project}"
        AND resource.labels.instance_id="${each.value.instance}"
        AND metric.type="redis.googleapis.com/stats/cpu_utilization"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = each.value.duration

      aggregations {
        alignment_period   = each.value.alignment_period
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
    display_name = "${local.memorystore_project} ${each.value.instance} - Instance CPU utilization ${each.value.severity} ${each.value.threshold * 100}%"
  }

  notification_channels = local.memorystore_notification_channels

  alert_strategy {
    auto_close = var.memorystore.auto_close
  }
}

# ----------------------
# Memorystore Redis Cluster CPU Utilization
# ----------------------
resource "google_monitoring_alert_policy" "memorystore_cluster_cpu" {
  for_each = local.memorystore_cluster_cpu_utilization

  project      = local.memorystore_project
  display_name = "${local.memorystore_project} ${each.value.cluster} - Cluster CPU utilization ${each.value.severity} ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter = <<-EOT
        resource.type="redis.googleapis.com/Cluster"
        AND resource.labels.project_id="${local.memorystore_project}"
        AND resource.labels.cluster_id="${each.value.cluster}"
        AND metric.type="redis.googleapis.com/cluster/stats/cpu_utilization"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = each.value.duration

      aggregations {
        alignment_period   = each.value.alignment_period
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
    display_name = "${local.memorystore_project} ${each.value.cluster} - Cluster CPU utilization ${each.value.severity} ${each.value.threshold * 100}%"
  }

  notification_channels = local.memorystore_notification_channels

  alert_strategy {
    auto_close = var.memorystore.auto_close
  }
}
