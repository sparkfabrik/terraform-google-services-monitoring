# ----------------------
# Memorystore
# ----------------------
locals {
  memorystore_project = var.memorystore.project_id != null ? var.memorystore.project_id : var.project_id

  memorystore_notification_channels = var.memorystore.notification_enabled ? (length(var.memorystore.notification_channels) > 0 ? var.memorystore.notification_channels : var.notification_channels) : []

  memorystore_instance_cpu_utilization = var.memorystore.enabled ? {
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
  } : {}

  memorystore_cluster_cpu_utilization = var.memorystore.enabled ? {
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
  } : {}

  memorystore_instance_memory_utilization = var.memorystore.enabled ? {
    for item in flatten(
      [
        for instance, instance_config in var.memorystore.instances : [
          for memory_utilization in instance_config.memory_utilization :
          merge(
            {
              "instance" : instance,
            },
            memory_utilization
          )
        ]
      ]
    ) : "${item.instance}--${item.severity}--${item.threshold}" => item
  } : {}

  memorystore_cluster_memory_utilization = var.memorystore.enabled ? {
    for item in flatten(
      [
        for cluster, cluster_config in var.memorystore.clusters : [
          for memory_utilization in cluster_config.memory_utilization :
          merge(
            {
              "cluster" : cluster,
            },
            memory_utilization
          )
        ]
      ]
    ) : "${item.cluster}--${item.severity}--${item.threshold}" => item
  } : {}

  memorystore_instance_connected_clients = var.memorystore.enabled ? {
    for item in flatten(
      [
        for instance, instance_config in var.memorystore.instances : [
          for connected_clients in instance_config.connected_clients :
          merge(
            {
              "instance" : instance,
            },
            connected_clients
          )
        ]
      ]
    ) : "${item.instance}--${item.severity}--${item.threshold}" => item
  } : {}

  memorystore_instance_uptime = var.memorystore.enabled ? {
    for item in flatten(
      [
        for instance, instance_config in var.memorystore.instances : [
          for uptime in instance_config.uptime :
          merge(
            {
              "instance" : instance,
            },
            uptime
          )
        ]
      ]
    ) : "${item.instance}--${item.severity}--${item.threshold}" => item
  } : {}
}

# ----------------------
# Memorystore Redis Instance CPU Utilization
# ----------------------
resource "google_monitoring_alert_policy" "memorystore_instance_cpu" {
  for_each = local.memorystore_instance_cpu_utilization

  project      = local.memorystore_project
  display_name = "Memorystore ${element(reverse(split("/", each.value.instance)), 0)} CPU utilization ${each.value.severity} > ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter = <<-EOT
        resource.type = "redis_instance"
        AND resource.labels.instance_id = "${each.value.instance}"
        AND metric.type = "redis.googleapis.com/stats/cpu_utilization_main_thread"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = each.value.duration

      aggregations {
        alignment_period     = each.value.alignment_period
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "resource.label.instance_id",
          "resource.label.node_id",
        ]
      }

      trigger {
        count = 1
      }
    }
    display_name = "Memorystore ${element(reverse(split("/", each.value.instance)), 0)} CPU utilization ${each.value.severity} > ${each.value.threshold * 100}%"
  }

  notification_channels = local.memorystore_notification_channels

  alert_strategy {
    auto_close = var.memorystore.auto_close
  }
}

# ----------------------
# Memorystore Redis Instance Memory Utilization
# ----------------------
resource "google_monitoring_alert_policy" "memorystore_instance_memory" {
  for_each = local.memorystore_instance_memory_utilization

  project      = local.memorystore_project
  display_name = "Memorystore ${element(reverse(split("/", each.value.instance)), 0)} Memory utilization ${each.value.severity} > ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter = <<-EOT
        resource.type = "redis_instance"
        AND resource.labels.instance_id = "${each.value.instance}"
        AND metric.type = "redis.googleapis.com/stats/memory/system_memory_usage_ratio"
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
    display_name = "Memorystore ${element(reverse(split("/", each.value.instance)), 0)} Memory utilization ${each.value.severity} > ${each.value.threshold * 100}%"
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
  display_name = "Memorystore ${element(reverse(split("/", each.value.cluster)), 0)} CPU utilization ${each.value.severity} > ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter = <<-EOT
        resource.type = "redis_cluster"
        AND resource.labels.cluster_id = "${each.value.cluster}"
        AND metric.type = "redis.googleapis.com/cluster/stats/cpu_utilization"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = each.value.duration

      aggregations {
        alignment_period     = each.value.alignment_period
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "resource.label.cluster_id",
          "resource.label.node_id",
        ]
      }

      trigger {
        count = 1
      }
    }
    display_name = "Memorystore ${element(reverse(split("/", each.value.cluster)), 0)} CPU utilization ${each.value.severity} > ${each.value.threshold * 100}%"
  }

  notification_channels = local.memorystore_notification_channels

  alert_strategy {
    auto_close = var.memorystore.auto_close
  }
}

# ----------------------
# Memorystore Redis Cluster Memory Utilization
# ----------------------
resource "google_monitoring_alert_policy" "memorystore_cluster_memory" {
  for_each = local.memorystore_cluster_memory_utilization

  project      = local.memorystore_project
  display_name = "Memorystore ${element(reverse(split("/", each.value.cluster)), 0)} Memory utilization ${each.value.severity} > ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter = <<-EOT
        resource.type = "redis_cluster"
        AND resource.labels.cluster_id = "${each.value.cluster}"
        AND metric.type = "redis.googleapis.com/cluster/stats/memory/system_memory_usage_ratio"
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
    display_name = "Memorystore ${element(reverse(split("/", each.value.cluster)), 0)} Memory utilization ${each.value.severity} > ${each.value.threshold * 100}%"
  }

  notification_channels = local.memorystore_notification_channels

  alert_strategy {
    auto_close = var.memorystore.auto_close
  }
}

# ----------------------
# Memorystore Redis Instance Connected Clients
# ----------------------
resource "google_monitoring_alert_policy" "memorystore_instance_connected_clients" {
  for_each = local.memorystore_instance_connected_clients

  project      = local.memorystore_project
  display_name = "Memorystore ${element(reverse(split("/", each.value.instance)), 0)} Connected clients ${each.value.severity} > ${each.value.threshold}"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter = <<-EOT
        resource.type = "redis_instance"
        AND resource.labels.instance_id = "${each.value.instance}"
        AND metric.type = "redis.googleapis.com/stats/connected_clients"
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
    display_name = "Memorystore ${element(reverse(split("/", each.value.instance)), 0)} Connected clients ${each.value.severity} > ${each.value.threshold}"
  }

  notification_channels = local.memorystore_notification_channels

  alert_strategy {
    auto_close = var.memorystore.auto_close
  }
}

# ----------------------
# Memorystore Redis Instance Uptime (restart detection)
# ----------------------
resource "google_monitoring_alert_policy" "memorystore_instance_uptime" {
  for_each = local.memorystore_instance_uptime

  project      = local.memorystore_project
  display_name = "Memorystore ${element(reverse(split("/", each.value.instance)), 0)} Uptime ${each.value.severity} < ${each.value.threshold}s"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter = <<-EOT
        resource.type = "redis_instance"
        AND resource.labels.instance_id = "${each.value.instance}"
        AND metric.type = "redis.googleapis.com/stats/uptime"
      EOT

      comparison      = "COMPARISON_LT"
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
    display_name = "Memorystore ${element(reverse(split("/", each.value.instance)), 0)} Uptime ${each.value.severity} < ${each.value.threshold}s"
  }

  notification_channels = local.memorystore_notification_channels

  alert_strategy {
    auto_close = var.memorystore.auto_close
  }
}
