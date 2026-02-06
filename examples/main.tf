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
  source = "github.com/sparkfabrik/terraform-google-services-monitoring?ref=0.9.0"

  notification_channels = var.notification_channels
  project_id            = var.project_id
  cloud_sql             = local.cloud_sql
  kyverno = {
    cluster_name          = "test-cluster"
    notification_channels = []
    # Exclude specific message patterns from the default set (matches against jsonPayload.message)
    error_patterns_exclude = [
      "failed to start watcher",
      "failed to list resources",
    ]
    # Add custom regex message patterns to the default set (matched against jsonPayload.message)
    # Note: These options only support message pattern matching. Arbitrary log filter conditions
    # (e.g., negative filters like -textPayload:"...") are not supported.
    # error_patterns_include = [
    #   "my custom.*error",
    #   "failed to connect.*database",
    # ]
  }
  cert_manager = {
    cluster_name = "test-cluster"
    namespace    = "cert-manager"
  }

  typesense = {
    cluster_name = "test-cluster"
    apps = {
      "typesense-app" = {
        uptime_check = {
          host = "typesense.example.com"
        }
        container_check = {
          enabled   = true
          namespace = "typesense"
          pod_restart = {
            threshold = 1
          }
        }
      }
    }
  }

  litellm = {
    cluster_name = "test-cluster"
    apps = {
      "litellm-app" = {
        uptime_check = {
          host = "litellm.example.com"
        }
        container_check = {
          namespace = "litellm"
          pod_restart = {
            threshold            = 2
            duration             = 300
            notification_prompts = ["CLOSED"]
          }
        }
      }
    }
  }
  memorystore = {
    enabled    = true
    project_id = "my-gcp-project"

    instances = {
      "my-redis-instance-1" = {
        cpu_utilization = [
          {
            severity         = "WARNING"
            threshold        = 0.80
            alignment_period = "300s"
            duration         = "300s"
          },
          {
            severity         = "CRITICAL"
            threshold        = 0.90
            alignment_period = "300s"
            duration         = "300s"
          }
        ]
      }
      "my-redis-instance-2" = {
        # Use default thresholds (WARNING at 80%, CRITICAL at 90%)
        cpu_utilization = []
      }
    }

    clusters = {
      "my-redis-cluster-1" = {
        cpu_utilization = [
          {
            threshold = 0.85
            duration  = "600s"
          },
          {
            severity  = "CRITICAL"
            threshold = 0.95
            duration  = "300s"
          }
        ]
      }
    }
  }
}
