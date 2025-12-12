# Terraform GCP Services Monitoring Module

This module creates a set of monitoring alerts for Google Cloud Platform services.

Supported services:

- Cloud SQL

  - CPU usage
  - Storage usage
  - Memory usage

- Kyverno

  - Error logs for admission-controller, background-controller, cleanup-controller, reports-controller

- cert-manager
  - Error logs for cert-manager controller when an Issuer or ClusterIssuer is missing

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
| <a name="input_cert_manager"></a> [cert\_manager](#input\_cert\_manager) | Configuration for cert-manager missing issuer log alert. Allows customization of project, cluster, namespace, notification channels, alert documentation, enablement, extra filters, auto-close timing, and notification rate limiting. | <pre>object({<br/>    enabled                          = optional(bool, true)<br/>    cluster_name                     = string<br/>    project_id                       = optional(string, null)<br/>    namespace                        = optional(string, "cert-manager")<br/>    notification_enabled             = optional(bool, true)<br/>    notification_channels            = optional(list(string), [])<br/>    logmatch_notification_rate_limit = optional(string, "300s")<br/>    alert_documentation              = optional(string, null)<br/>    auto_close_seconds               = optional(number, 3600)<br/>    filter_extra                     = optional(string, "")<br/>  })</pre> | n/a | yes |
| <a name="input_cloud_sql"></a> [cloud\_sql](#input\_cloud\_sql) | Configuration for Cloud SQL monitoring alerts. Supports customization of project, auto-close timing, notification channels, and per-instance alert thresholds for CPU, memory, and disk utilization. | <pre>object({<br/>    project_id            = optional(string, null)<br/>    auto_close            = optional(string, "86400s") # default 24h<br/>    notification_enabled  = optional(bool, true)<br/>    notification_channels = optional(list(string), [])<br/>    instances = optional(map(object({<br/>      cpu_utilization = optional(list(object({<br/>        severity         = optional(string, "WARNING"),<br/>        threshold        = optional(number, 0.90)<br/>        alignment_period = optional(string, "120s")<br/>        duration         = optional(string, "300s")<br/>        })), [<br/>        {<br/>          threshold = 0.85,<br/>          duration  = "1200s",<br/>        },<br/>        {<br/>          severity         = "CRITICAL",<br/>          threshold        = 1,<br/>          duration         = "300s",<br/>          alignment_period = "60s",<br/>        }<br/>      ])<br/>      memory_utilization = optional(list(object({<br/>        severity         = optional(string, "WARNING"),<br/>        threshold        = optional(number, 0.90)<br/>        alignment_period = optional(string, "300s")<br/>        duration         = optional(string, "300s")<br/>        })), [<br/>        {<br/>          severity = "WARNING",<br/>        },<br/>        {<br/>          severity  = "CRITICAL",<br/>          threshold = 0.95,<br/>        }<br/>      ])<br/>      disk_utilization = optional(list(object({<br/>        severity         = optional(string, "WARNING"),<br/>        threshold        = optional(number, 0.85)<br/>        alignment_period = optional(string, "300s")<br/>        duration         = optional(string, "600s")<br/>        })), [<br/>        {<br/>          severity = "WARNING",<br/>        },<br/>        {<br/>          severity  = "CRITICAL",<br/>          threshold = 0.95,<br/>        }<br/>      ])<br/>    })), {})<br/>  })</pre> | n/a | yes |
| <a name="input_kyverno"></a> [kyverno](#input\_kyverno) | Configuration for Kyverno monitoring alerts. Allows customization of cluster name, project, notification channels, alert documentation, metric thresholds, auto-close timing, enablement, extra filters, and namespace. | <pre>object({<br/>    enabled               = optional(bool, true)<br/>    cluster_name          = string<br/>    project_id            = optional(string, null)<br/>    notification_enabled  = optional(bool, true)<br/>    notification_channels = optional(list(string), [])<br/>    # Rate limit for notifications, e.g. "300s" for 5 minutes, used only for log match alerts<br/>    logmatch_notification_rate_limit = optional(string, "300s")<br/>    alert_documentation              = optional(string, null)<br/>    auto_close_seconds               = optional(number, 3600)<br/>    filter_extra                     = optional(string, "")<br/>    namespace                        = optional(string, "kyverno")<br/>  })</pre> | n/a | yes |
| <a name="input_litellm"></a> [litellm](#input\_litellm) | Configuration for LiteLLM monitoring alerts. Supports uptime checks for HTTP endpoints and container-level alerts (pod restarts) in GKE. Each app is identified by its name (map key). | <pre>object({<br/>    enabled               = optional(bool, false)<br/>    project_id            = optional(string, null)<br/>    notification_enabled  = optional(bool, true)<br/>    notification_channels = optional(list(string), [])<br/>    cluster_name          = optional(string, null)<br/><br/>    apps = optional(map(object({<br/>      uptime_check = optional(object({<br/>        enabled = optional(bool, true)<br/>        host    = string<br/>        path    = optional(string, "/health/readiness")<br/>      }), null)<br/><br/>      container_check = optional(object({<br/>        enabled   = optional(bool, true)<br/>        namespace = string<br/>        pod_restart = optional(object({<br/>          threshold          = optional(number, 0)<br/>          alignment_period   = optional(number, 60)<br/>          duration           = optional(number, 0)<br/>          auto_close_seconds = optional(number, 3600)<br/>        }), {})<br/>      }), null)<br/>    })), {})<br/>  })</pre> | `{}` | no |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | List of notification channel IDs to notify when an alert is triggered | `list(string)` | `[]` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The Google Cloud project ID where logging exclusions will be created | `string` | n/a | yes |
| <a name="input_ssl_alert"></a> [ssl\_alert](#input\_ssl\_alert) | Configuration for SSL certificate expiration alerts. Allows customization of project, notification channels, alert thresholds, and user labels. | <pre>object({<br/>    enabled               = optional(bool, false)<br/>    project_id            = optional(string, null)<br/>    notification_enabled  = optional(bool, true)<br/>    notification_channels = optional(list(string), [])<br/>    threshold_days        = optional(list(number), [15, 7])<br/>    user_labels           = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_typesense"></a> [typesense](#input\_typesense) | Configuration for Typesense monitoring alerts. Supports uptime checks for HTTP endpoints and container-level alerts (pod restarts) in GKE. Each app is identified by its name (map key). | <pre>object({<br/>    enabled               = optional(bool, false)<br/>    project_id            = optional(string, null)<br/>    notification_enabled  = optional(bool, true)<br/>    notification_channels = optional(list(string), [])<br/>    cluster_name          = optional(string, null) # GKE cluster name for container checks<br/><br/>    # Apps configuration - map keyed by app_name<br/>    apps = optional(map(object({<br/>      # Uptime check configuration (optional)<br/>      uptime_check = optional(object({<br/>        enabled = optional(bool, true)<br/>        host    = string<br/>        path    = optional(string, "/readyz")<br/>      }), null)<br/><br/>      # Container check configuration for GKE (optional)<br/>      container_check = optional(object({<br/>        enabled   = optional(bool, true)<br/>        namespace = string<br/>        pod_restart = optional(object({<br/>          threshold          = optional(number, 0)<br/>          alignment_period   = optional(number, 60)<br/>          duration           = optional(number, 0)<br/>          auto_close_seconds = optional(number, 3600)<br/>        }), {})<br/>      }), null)<br/>    })), {})<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloud_sql_cpu_utilization"></a> [cloud\_sql\_cpu\_utilization](#output\_cloud\_sql\_cpu\_utilization) | n/a |
| <a name="output_cloud_sql_disk_utilization"></a> [cloud\_sql\_disk\_utilization](#output\_cloud\_sql\_disk\_utilization) | n/a |
| <a name="output_cloud_sql_memory_utilization"></a> [cloud\_sql\_memory\_utilization](#output\_cloud\_sql\_memory\_utilization) | n/a |
| <a name="output_ssl_alert_policy_names"></a> [ssl\_alert\_policy\_names](#output\_ssl\_alert\_policy\_names) | n/a |

## Resources

| Name | Type |
|------|------|
| [google_monitoring_alert_policy.cert_manager_logmatch_alert](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.cloud_sql_cpu_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.cloud_sql_disk_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.cloud_sql_memory_utilization](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.kyverno_logmatch_alert](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.litellm_pod_restart](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.ssl_expiring_days](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.typesense_pod_restart](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_litellm_uptime_checks"></a> [litellm\_uptime\_checks](#module\_litellm\_uptime\_checks) | github.com/sparkfabrik/terraform-sparkfabrik-gcp-http-monitoring | 1.0.0 |
| <a name="module_typesense_uptime_checks"></a> [typesense\_uptime\_checks](#module\_typesense\_uptime\_checks) | github.com/sparkfabrik/terraform-sparkfabrik-gcp-http-monitoring | 1.0.0 |

<!-- END_TF_DOCS -->
