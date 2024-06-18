
variable "project" {
  type    = string
  default = ""
}

variable "notification_channels" {
  type    = list(string)
  default = []
}
