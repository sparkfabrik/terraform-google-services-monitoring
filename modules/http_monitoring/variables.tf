variable "gcp_project_id" {
  type        = string
  description = "The Google Cloud project ID."
}

variable "uptime_monitoring_display_name" {
  type        = string
  description = "A human-friendly name for the uptime check configuration. Used for monitoring display_name."
  default     = ""
}

variable "uptime_monitoring_path" {
  type        = string
  description = "The path to the page to run the check against."
  default     = "/"
}

variable "uptime_check_period" {
  type        = string
  description = "How often, in seconds, the uptime check is performed. Currently, the only supported values are 60s (1 minute), 300s (5 minutes), 600s (10 minutes), and 900s (15 minutes). Defaults to 300s."
  default     = "60s"
}

variable "uptime_check_timeout" {
  type        = string
  description = "The maximum amount of time to wait for the request to complete (must be between 1 and 60 seconds)."
  default     = "10s"
}

variable "uptime_monitoring_host" {
  type        = string
  description = "A hostname to monitor (without protocol, example: 'www.my-site.com')."
}

variable "uptime_check_regions" {
  type        = list(string)
  description = "The list of regions from which the check will be run. Some regions contain one location, and others contain more than one. If this field is specified, enough regions to include a minimum of 3 locations must be provided, or an error message is returned. Not specifying this field will result in uptime checks running from all regions."
  default     = ["USA_VIRGINIA", "EUROPE", "ASIA_PACIFIC"]
}

variable "uptime_alert_user_labels" {
  type        = map(string)
  description = "This field is intended to be used for labelling the SSL alerts. Labels and values can contain only lowercase letters, numerals, underscores, and dashes. Keys must begin with a letter."
  default     = {}
}

variable "uptime_monitoring_headers" {
  type        = map(string)
  description = "A set of key/value header pairs to send in the HTTP request to the URL."
  default     = {}
}

variable "alert_threshold_duration" {
  type        = string
  description = "The amount of time that a time series must violate the threshold to be considered failing. Currently, only values that are a multiple of a minute--e.g., 0, 60, 120, or 300 seconds--are supported."
  default     = "60s"
}

variable "alert_threshold_value" {
  type        = number
  description = "A value against which to compare the time series."
  default     = 1
}

variable "alert_notification_channels" {
  type        = list(string)
  description = "Identifies the notification channels to which notifications should be sent when incidents are opened or closed. The syntax of the entries in this field is projects/[PROJECT_ID]/notificationChannels/[CHANNEL_ID]"
}

variable "alert_display_name" {
  type        = string
  description = "A human-friendly name for the alert policy. Used for monitoring display_name."
  default     = ""
}

variable "accepted_response_status_values" {
  description = "Check will only pass if the HTTP response status code is in this set of status values (combined with the set of status classes)."
  type        = set(number)
  default     = []
}

variable "accepted_response_status_classes" {
  description = "Check will only pass if the HTTP response status code is in this set of status classes (combined with the set of status values). Possible values: STATUS_CLASS_1XX, STATUS_CLASS_2XX, STATUS_CLASS_3XX, STATUS_CLASS_4XX, STATUS_CLASS_5XX, STATUS_CLASS_ANY"
  type        = set(string)
  default     = []
}
