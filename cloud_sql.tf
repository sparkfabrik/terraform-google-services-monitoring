# ----------------------
# CloudSQL
# ----------------------
locals {
  # Use the cloud_sql project if specified, otherwise use the project.
  cloud_sql_project = var.cloud_sql.project_id != null ? var.cloud_sql.project_id : var.project_id

  # Use the cloud_sql notification channels for if not specified in the configuration.
  cloud_sql_notification_channels = var.cloud_sql.notification_enabled ? (length(var.cloud_sql.notification_channels) > 0 ? var.cloud_sql.notification_channels : var.notification_channels) : []

  cloud_sql_cpu_utilization = {
    for item in flatten(
      [
        for instance, instance_config in var.cloud_sql.instances : [
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

  cloud_sql_memory_utilization = {
    for item in flatten(
      [
        for instance, instance_config in var.cloud_sql.instances : [
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
  }

  cloud_sql_disk_utilization = {
    for item in flatten(
      [
        for instance, instance_config in var.cloud_sql.instances : [
          for disk_utilization in instance_config.disk_utilization :
          merge(
            {
              "instance" : instance,
            },
            disk_utilization
          )
        ]
      ]
    ) : "${item.instance}--${item.severity}--${item.threshold}" => item
  }
}

# ----------------------
# CloudSQL CPU utilization
# ----------------------
resource "google_monitoring_alert_policy" "cloud_sql_cpu_utilization" {
  for_each = local.cloud_sql_cpu_utilization

  display_name = "${local.cloud_sql_project} ${each.value.instance} - CPU utilization ${each.value.severity} ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${local.cloud_sql_project}:${each.value.instance}\" AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = each.value.duration
      trigger {
        count = 1
      }
      aggregations {
        alignment_period   = each.value.alignment_period
        per_series_aligner = "ALIGN_MEAN"
      }
    }
    display_name = "${local.cloud_sql_project} ${each.value.instance} - CPU utilization ${each.value.severity} ${each.value.threshold * 100}%"
  }
  alert_strategy {
    auto_close = var.cloud_sql.auto_close
  }
  notification_channels = local.cloud_sql_notification_channels
}

# ----------------------
# CloudSQL Memory utilization
# ----------------------
resource "google_monitoring_alert_policy" "cloud_sql_memory_utilization" {
  for_each = local.cloud_sql_memory_utilization

  display_name = "${local.cloud_sql_project} ${each.value.instance} - Memory utilization ${each.value.severity} ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity
  conditions {
    display_name = "${local.cloud_sql_project} ${each.value.instance} - Memory utilization ${each.value.severity} ${each.value.threshold * 100}%"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${local.cloud_sql_project}:${each.value.instance}\" AND metric.type = \"cloudsql.googleapis.com/database/memory/utilization\""
      duration        = each.value.duration
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold

      aggregations {
        alignment_period   = each.value.alignment_period
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = var.cloud_sql.auto_close
  }

  notification_channels = local.cloud_sql_notification_channels
}

# ----------------------
# CloudSQL disk utilization
# ----------------------
resource "google_monitoring_alert_policy" "cloud_sql_disk_utilization" {
  for_each = local.cloud_sql_disk_utilization

  display_name = "${local.cloud_sql_project} ${each.value.instance} - Disk utilization ${each.value.severity} ${each.value.threshold * 100}%"
  combiner     = "OR"
  severity     = each.value.severity

  conditions {
    display_name = "${local.cloud_sql_project} ${each.value.instance} - Disk utilization ${each.value.severity} ${each.value.threshold * 100}%"
    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${local.cloud_sql_project}:${each.value.instance}\" AND metric.type = \"cloudsql.googleapis.com/database/disk/utilization\""
      duration        = each.value.duration
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold

      aggregations {
        alignment_period   = each.value.alignment_period
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = var.cloud_sql.auto_close
  }
  notification_channels = local.cloud_sql_notification_channels
}
