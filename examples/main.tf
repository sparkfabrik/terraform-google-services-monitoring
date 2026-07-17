/*
   # A simple example on how to use this module
 */

locals {
  # Enable all Cloud SQL monitorings on selected instances, eg.
  cloud_sql = {
    instances = {
      "master-instance" = {}
      "stage-instance"  = {}
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
  source = "../"

  notification_channels = var.notification_channels
  project_id            = var.project_id
  cloud_sql             = local.cloud_sql
  konnectivity_agent = {
    cluster_name = "test-cluster"
  }
  kyverno = {
    cluster_name          = "test-cluster"
    notification_channels = []
    # Level-1 restart alert, two-tier service-error alerts and the broken-policy
    # engine alert are all enabled by default. Thresholds can be overridden per check,
    # and the tier-1 noise exclusions extended:
    # service_errors_check = { threshold = 5, noise_exclusions = ["connection refused"] }
    # volume_check         = { threshold = 10 }
    # engine_check         = { threshold = 0 }
  }
  cert_manager = {
    cluster_name = "test-cluster"
    namespace    = "cert-manager"
  }

  typesense = {
    cluster_name        = "test-cluster"
    alert_documentation = "Typesense runbook: https://runbooks.example.com/typesense"
    apps = {
      "typesense-app" = {
        namespace = "typesense"
        uptime_check = {
          host          = "typesense.example.com"
          content_match = "\"cluster_status\":\"OK\""
        }
        container_check = {
          enabled = true
          pod_restart = {
            threshold = 1
          }
        }
        log_check = {
          enabled                                  = true
          min_severity                             = "ERROR"
          logmatch_notification_rate_limit_seconds = 300
          auto_close_seconds                       = 3600
        }
        flood_check = {
          enabled                      = true
          threshold_entries_per_minute = 3000
          alignment_period_seconds     = 60
          duration_seconds             = 300
          auto_close_seconds           = 86400
        }
        # Workload vitals with curated defaults: memory WARNING 85% / CRITICAL 95%,
        # CPU WARNING 90%, volume WARNING 75% / CRITICAL 85%, replica availability
        # CRITICAL below raft quorum and WARNING below expected_replicas.
        workload_check = {
          expected_replicas = 3
        }
      }
      # Second app on another GKE cluster (per-app override of the service-level
      # cluster_name), with every workload_check field customized.
      "typesense-app-2" = {
        cluster_name = "other-cluster"
        namespace    = "typesense-2"
        workload_check = {
          expected_replicas = 1
          container_name    = "typesense"
          controller_name   = "typesense-2-sts"
          volume_name       = "storage"
          # Severity is case-insensitive; the module normalizes it to uppercase.
          memory_utilization = [
            {
              severity                 = "critical"
              threshold                = 0.90
              alignment_period_seconds = 300
              duration_seconds         = 300
            }
          ]
          cpu_utilization = [] # family disabled
          volume_utilization = [
            {
              threshold = 0.80
            }
          ]
          replica_availability = {
            enabled          = true
            duration_seconds = 120
          }
          auto_close_seconds   = 7200
          notification_prompts = ["CLOSED"]
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
      # Use default thresholds (memory_utilization CRITICAL at 80%)
      "my-redis-instance-2" = {}
    }

    clusters = {
      "my-redis-cluster-1" = {
        cpu_utilization = [
          {
            threshold = 0.85
            duration  = "600s"
          }
        ]
      }
    }
  }
}
