output "cloud_sql_disk_utilization" {
  value = { for k, v in google_monitoring_alert_policy.cloud_sql_disk_utilization : k => v.name }
}

output "cloud_sql_memory_utilization" {
  value = { for k, v in google_monitoring_alert_policy.cloud_sql_memory_utilization : k => v.name }
}

output "cloud_sql_cpu_utilization" {
  value = { for k, v in google_monitoring_alert_policy.cloud_sql_cpu_utilization : k => v.name }
}
