
variable "project_id" {
  description = "The Google Cloud project ID where logging exclusions will be created"
  type        = string
}

variable "notification_channels" {
  description = "List of notification channel IDs to notify when an alert is triggered"
  type        = list(string)
  default     = []
}

# Note: kyverno, cert_manager, typesense, litellm and memorystore are passed to the
# module as literals in main.tf (the canonical usage reference), so they are not
# declared as root variables here.
