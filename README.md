# Terraform GCP Services Monitoring Module

This module creates a set of monitoring alerts for Google Cloud Platform services.

Supported services:

- Cloud SQL

  - CPU usage
  - Storage usage
  - Memory usage

- Kyverno

  - Error logs for admission-controller, background-controller, cleanup-controller, reports-controller
  - Metric threshold (optional)

<!-- BEGIN_TF_DOCS -->
## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 5.10 |

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 5.10 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud_sql"></a> [cloud\_sql](#input\_cloud\_sql) | Configuration for Cloud SQL monitoring alerts. Supports customization of project, auto-close timing, notification channels, and per-instance alert thresholds for CPU, memory, and disk utilization. | <pre>object({<br/>    project_id            = optional(string, null)<br/>    auto_close            = optional(string, "86400s") # default 24h<br/>    notification_enabled  = optional(bool, true)<br/>    notification_channels = optional(list(string), [])<br/>    instances = optional(map(object({<br/>      cpu_utilization = optional(list(object({<br/>        severity         = optional(string, "WARNING"),<br/>        threshold        = optional(number, 0.90)<br/>        alignment_period = optional(string, "120s")<br/>        duration         = optional(string, "300s")<br/>        })), [<br/>        {<br/>          threshold = 0.85,<br/>          duration  = "1200s",<br/>        },<br/>        {<br/>          severity         = "CRITICAL",<br/>          threshold        = 1,<br/>          duration         = "300s",<br/>          alignment_period = "60s",<br/>        }<br/>      ])<br/>      memory_utilization = optional(list(object({<br/>        severity         = optional(string, "WARNING"),<br/>        threshold        = optional(number, 0.90)<br/>        alignment_period = optional(string, "300s")<br/>        duration         = optional(string, "300s")<br/>        })), [<br/>        {<br/>          severity = "WARNING",<br/>        },<br/>        {<br/>          severity  = "CRITICAL",<br/>          threshold = 0.95,<br/>        }<br/>      ])<br/>      disk_utilization = optional(list(object({<br/>        severity         = optional(string, "WARNING"),<br/>        threshold        = optional(number, 0.85)<br/>        alignment_period = optional(string, "300s")<br/>        duration         = optional(string, "600s")<br/>        })), [<br/>        {<br/>          severity = "WARNING",<br/>        },<br/>        {<br/>          severity  = "CRITICAL",<br/>          threshold = 0.95,<br/>        }<br/>      ])<br/>    })), {})<br/>  })</pre> | n/a | yes |
| <a name="input_kyverno"></a> [kyverno](#input\_kyverno) | Configuration for Kyverno monitoring alerts. Allows customization of cluster name, project, notification channels, alert documentation, metric thresholds, auto-close timing, enablement, extra filters, and namespace. | <pre>object({<br/>    cluster_name          = string<br/>    project_id            = optional(string, null)<br/>    notification_enabled  = optional(bool, true)<br/>    notification_channels = optional(list(string), [])<br/>    # Rate limit for notifications, e.g. "300s" for 5 minutes, used only for log match alerts<br/>    logmatch_notification_rate_limit = optional(string, "300s")<br/>    alert_documentation              = optional(string, null)<br/>    # If true, use a metric threshold alert instead of log match alert otherwise use log match alert<br/>    use_metric_threshold    = optional(bool, false)<br/>    metric_threshold_count  = optional(number, 2)<br/>    metric_lookback_minutes = optional(number, 1)<br/>    auto_close_seconds      = optional(number, 3600)<br/>    enabled                 = optional(bool, true)<br/>    filter_extra            = optional(string, "")<br/>    namespace               = optional(string, "kyverno")<br/>  })</pre> | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | List of notification channel IDs to notify when an alert is triggered | `list(string)` | `[]` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The Google Cloud project ID where logging exclusions will be created | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloud_sql_cpu_utilization"></a> [cloud\_sql\_cpu\_utilization](#output\_cloud\_sql\_cpu\_utilization) | n/a |
| <a name="output_cloud_sql_disk_utilization"></a> [cloud\_sql\_disk\_utilization](#output\_cloud\_sql\_disk\_utilization) | n/a |
| <a name="output_cloud_sql_memory_utilization"></a> [cloud\_sql\_memory\_utilization](#output\_cloud\_sql\_memory\_utilization) | n/a |

## Resources

| Name | Type |
|------|------|
| [google_logging_metric.kyverno_error_metric](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_monitoring_alert_policy.cloud_sql_cpu_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.cloud_sql_disk_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.cloud_sql_memory_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.kyverno_logmatch_alert](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.kyverno_metric_threshold_alert](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |

## Modules

No modules.

<!-- END_TF_DOCS -->
