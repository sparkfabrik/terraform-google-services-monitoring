variable "project" {
  type    = string
  default = null
}

variable "notification_channels" {
  type    = list(string)
  default = []
}

variable "auto_close" {
  type    = string
  default = "86400s" # 24h
}

variable "cloud_sql" {
  type = object({
    project               = optional(string, null)
    auto_close            = optional(string, null)
    notification_channels = optional(list(string), [])
    instances = optional(map(object({
      cpu_utilization = optional(list(object({
        severity         = optional(string, "WARNING"),
        threshold        = optional(number, 0.90)
        alignment_period = optional(string, "120s")
        duration         = optional(string, "300s")
        })), [
        {
          threshold = 0.85,
          duration  = "1200s",
        },
        {
          severity  = "CRITICAL",
          threshold = 1,
          duration  = "300s",
          alignment_period = "60s",
        }
      ])
      memory_utilization = optional(list(object({
        severity         = optional(string, "WARNING"),
        threshold        = optional(number, 0.90)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "300s")
        })), [
        {
          severity  = "WARNING",
        },
        {
          severity  = "CRITICAL",
          threshold = 0.95,
        }
      ])
      disk_utilization = optional(list(object({
        severity         = optional(string, "WARNING"),
        threshold        = optional(number, 0.85)
        alignment_period = optional(string, "300s")
        duration         = optional(string, "600s")
        })), [
        {
          severity  = "WARNING",
        },
        {
          severity  = "CRITICAL",
          threshold = 0.95,          
        }
      ])
    })), {})
  })
}
