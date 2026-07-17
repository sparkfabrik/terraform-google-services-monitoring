output "cloud_sql_disk_utilization" {
  value = { for k, v in google_monitoring_alert_policy.cloud_sql_disk_utilization : k => v.name }
}

output "cloud_sql_memory_utilization" {
  value = { for k, v in google_monitoring_alert_policy.cloud_sql_memory_utilization : k => v.name }
}

output "cloud_sql_cpu_utilization" {
  value = { for k, v in google_monitoring_alert_policy.cloud_sql_cpu_utilization : k => v.name }
}

output "memorystore_instance_cpu_utilization" {
  value = { for k, v in google_monitoring_alert_policy.memorystore_instance_cpu : k => v.name }
}

output "memorystore_instance_memory_utilization" {
  value = { for k, v in google_monitoring_alert_policy.memorystore_instance_memory : k => v.name }
}

output "memorystore_cluster_cpu_utilization" {
  value = { for k, v in google_monitoring_alert_policy.memorystore_cluster_cpu : k => v.name }
}

output "memorystore_cluster_memory_utilization" {
  value = { for k, v in google_monitoring_alert_policy.memorystore_cluster_memory : k => v.name }
}

output "ssl_alert_policy_names" {
  value = { for days, alert in google_monitoring_alert_policy.ssl_expiring_days : days => alert.name }
}

output "typesense_logmatch_alert_policy_names" {
  value = { for k, v in google_monitoring_alert_policy.typesense_logmatch_alert : k => v.name }
}

output "typesense_flood_alert_policy_names" {
  value = { for k, v in google_monitoring_alert_policy.typesense_flood_alert : k => v.name }
}

output "typesense_workload_memory_alert_policy_names" {
  value = { for k, v in google_monitoring_alert_policy.typesense_workload_memory : k => v.name }
}

output "typesense_workload_cpu_alert_policy_names" {
  value = { for k, v in google_monitoring_alert_policy.typesense_workload_cpu : k => v.name }
}

output "typesense_workload_volume_alert_policy_names" {
  value = { for k, v in google_monitoring_alert_policy.typesense_workload_volume : k => v.name }
}

output "typesense_workload_replicas_alert_policy_names" {
  value = { for k, v in google_monitoring_alert_policy.typesense_workload_replicas : k => v.name }
}

output "typesense_dashboard_ids" {
  value = { for k, v in google_monitoring_dashboard.typesense_app : k => v.id }
}
