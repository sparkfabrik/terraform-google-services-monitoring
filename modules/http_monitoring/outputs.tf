output "uptime_check_id" {
  description = "Identifier of the created uptime check config, as referenced by the 'check_id' metric label of uptime check time series."
  value       = google_monitoring_uptime_check_config.https_uptime.uptime_check_id
}
