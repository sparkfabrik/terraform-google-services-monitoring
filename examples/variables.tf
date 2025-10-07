
variable "project" {
  type    = string
  default = "test-project"
}

variable "notification_channels" {
  type    = list(string)
  default = []
}

variable "kyverno" {
  description = "Configurazione completa del monitoraggio Kyverno"
  type = object({
    cluster_name            = string
    project_id              = optional(string, null)
    notification_channels   = optional(list(string), [])
    alert_documentation     = optional(string, "Kyverno controllers produced ERROR logs in namespace kyverno.")
    use_metric_threshold    = optional(bool, true)
    metric_threshold_count  = optional(number, 2)
    metric_lookback_minutes = optional(number, 1)
    auto_close_seconds      = optional(number, 3600)
    enabled                 = optional(bool, true)
    filter_extra            = optional(string, "")
    namespace               = optional(string, "kyverno")
  })
}
