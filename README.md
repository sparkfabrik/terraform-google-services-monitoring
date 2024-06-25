# Terraform GCP Services Monitoring Module

This module creates a set of monitoring alerts for Google Cloud Platform services.

Supported services:

- Cloud SQL
  - CPU usage
  - Storage usage
  - Memory usage

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
| <a name="input_auto_close"></a> [auto\_close](#input\_auto\_close) | n/a | `string` | `"86400s"` | no |
| <a name="input_cloud_sql"></a> [cloud\_sql](#input\_cloud\_sql) | n/a | <pre>object({<br>    project               = optional(string, null)<br>    auto_close            = optional(string, null)<br>    notification_channels = optional(list(string), [])<br>    instances = optional(map(object({<br>      cpu_utilization = optional(list(object({<br>        severity         = optional(string, "CRITICAL"),<br>        threshold        = optional(number, 0.90)<br>        alignment_period = optional(string, "120s")<br>        duration         = optional(string, "300s")<br>        })), [<br>        {<br>          severity  = "WARNING",<br>          threshold = 0.85,<br>          duration  = "1200s",<br>        },<br>        {<br>          severity  = "CRITICAL",<br>          threshold = 1,<br>          duration  = "300s",<br>          alignment_period = "60s",<br>        }<br>      ])<br>      memory_utilization = optional(list(object({<br>        severity         = optional(string, "CRITICAL"),<br>        threshold        = optional(number, 0.90)<br>        alignment_period = optional(string, "300s")<br>        duration         = optional(string, "300s")<br>        })), [<br>        {<br>          severity  = "WARNING",<br>          threshold = 0.80,<br>        },<br>        {<br>          severity  = "CRITICAL",<br>          threshold = 0.90,<br>        }<br>      ])<br>      disk_utilization = optional(list(object({<br>        severity         = optional(string, "CRITICAL"),<br>        threshold        = optional(number, 0.90)<br>        alignment_period = optional(string, "300s")<br>        duration         = optional(string, "600s")<br>        })), [<br>        {<br>          severity  = "WARNING",<br>          threshold = 0.85,<br>        },<br>        {<br>          severity  = "CRITICAL",<br>          threshold = 0.95,          <br>        }<br>      ])<br>    })), {})<br>  })</pre> | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | n/a | `list(string)` | `[]` | no |
| <a name="input_project"></a> [project](#input\_project) | n/a | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloud_sql_cpu_utilization"></a> [cloud\_sql\_cpu\_utilization](#output\_cloud\_sql\_cpu\_utilization) | n/a |
| <a name="output_cloud_sql_disk_utilization"></a> [cloud\_sql\_disk\_utilization](#output\_cloud\_sql\_disk\_utilization) | n/a |
| <a name="output_cloud_sql_memory_utilization"></a> [cloud\_sql\_memory\_utilization](#output\_cloud\_sql\_memory\_utilization) | n/a |

## Resources

| Name | Type |
|------|------|
| [google_monitoring_alert_policy.cloud_sql_cpu_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.cloud_sql_disk_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.cloud_sql_memory_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |

## Modules

No modules.


<!-- END_TF_DOCS -->
