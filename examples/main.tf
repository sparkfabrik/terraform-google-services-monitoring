/*
   # A simple example on how to use this module
 */

locals {
  # Enable all Cdoud SQL monitorings on selected instances, eg.
  cloud_sql = { 
    instances = { 
      (google_sql_database_instance.master.name) = {} 
      (google_sql_database_instance.stage.name)  = {}
    } 
  } 

  # Use custom Cloud SQL cpu monitoring on google_sql_database_instance.master.name
  # Use all default Cloud SQL monitoring on google_sql_database_instance.stage.name
  # cloud_sql = {
  #   instances = {
  #     (google_sql_database_instance.master.name) = {
  #       cpu_utilization = [{
  #         severity         = "ALERT"
  #         threshold        = 0.90
  #       }]
  #     }
  #     (google_sql_database_instance.stage.name)  = {}
  #   }
  # }

  # Disable Cloud SQL monitoring
  # cloud_sql = {
  #   instances = {}
  # }

  # Enable default Cloud SQL monitoring on instance google_sql_database_instance.master.name
  # Disable cpu utilization monitoring on instance google_sql_database_instance.stage.name
  # cloud_sql = {
  #   instances = {
  #     (google_sql_database_instance.master.stage) = { cpu_utilization = [] }
  #     (google_sql_database_instance.master.prod) = {} 
  #   }
  # }

}

module "example" {
  source  = "github.com/sparkfabrik/terraform-google-services-monitoring"
  version = ">= 0.1.0"

  notification_channels = var.notification_channels
  project = var.project
  cloud_sql = local.cloud_sql
}
