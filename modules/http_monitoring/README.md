# HTTP Monitoring Module

Terraform module for creating HTTPS uptime checks and alert policies in Google Cloud Monitoring.

## Features

- HTTPS uptime check with SSL validation
- Configurable check intervals and timeouts
- Multi-region monitoring (default: USA, Europe, Asia Pacific)
- Automatic alert policy on check failure
- Custom response status code validation

## Usage

```hcl
module "http_monitoring" {
  source = "./modules/http_monitoring"

  gcp_project_id              = "my-project"
  uptime_monitoring_host      = "www.example.com"
  uptime_monitoring_path      = "/health"
  alert_notification_channels = ["projects/my-project/notificationChannels/123456"]
}
```

## Inputs

| Name                               | Description                                           | Type           | Default                                      | Required |
| ---------------------------------- | ----------------------------------------------------- | -------------- | -------------------------------------------- | :------: |
| `gcp_project_id`                   | Google Cloud project ID                               | `string`       | -                                            |   yes    |
| `uptime_monitoring_host`           | Hostname to monitor (without protocol)                | `string`       | -                                            |   yes    |
| `alert_notification_channels`      | Notification channel IDs for alerts                   | `list(string)` | -                                            |   yes    |
| `uptime_monitoring_path`           | Path to check                                         | `string`       | `"/"`                                        |    no    |
| `uptime_monitoring_display_name`   | Display name for the uptime check                     | `string`       | `""`                                         |    no    |
| `uptime_check_period`              | Check interval (60s, 300s, 600s, 900s)                | `string`       | `"60s"`                                      |    no    |
| `uptime_check_timeout`             | Request timeout (1-60 seconds)                        | `string`       | `"10s"`                                      |    no    |
| `uptime_check_regions`             | Regions to run checks from                            | `list(string)` | `["USA_VIRGINIA", "EUROPE", "ASIA_PACIFIC"]` |    no    |
| `uptime_monitoring_headers`        | HTTP headers to send                                  | `map(string)`  | `{}`                                         |    no    |
| `uptime_alert_user_labels`         | Labels for the alert policy                           | `map(string)`  | `{}`                                         |    no    |
| `alert_threshold_duration`         | Duration before triggering alert                      | `string`       | `"60s"`                                      |    no    |
| `alert_threshold_value`            | Threshold for alert trigger                           | `number`       | `1`                                          |    no    |
| `alert_display_name`               | Display name for the alert                            | `string`       | `""`                                         |    no    |
| `accepted_response_status_values`  | Accepted HTTP status codes                            | `set(number)`  | `[]`                                         |    no    |
| `accepted_response_status_classes` | Accepted HTTP status classes (e.g., STATUS_CLASS_2XX) | `set(string)`  | `[]`                                         |    no    |

## Resources Created

- `google_monitoring_uptime_check_config.https_uptime` - HTTPS uptime check
- `google_monitoring_alert_policy.failure_alert` - Alert policy for check failures
