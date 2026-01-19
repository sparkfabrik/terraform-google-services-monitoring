locals {
  konnectivity_agent_project = (
    var.konnectivity_agent.project_id != null
    ? var.konnectivity_agent.project_id
    : var.project_id
  )

  konnectivity_agent_notification_channels = (
    var.konnectivity_agent.notification_enabled
    ? (
      length(var.konnectivity_agent.notification_channels) > 0
      ? var.konnectivity_agent.notification_channels
      : var.notification_channels
    )
    : []
  )
}

resource "google_monitoring_alert_policy" "konnectivity_agent_replicas" {
  count = var.konnectivity_agent.enabled && var.konnectivity_agent.cluster_name != null && var.konnectivity_agent.cluster_name != "" ? 1 : 0

  project      = local.konnectivity_agent_project
  display_name = "CRITICAL: Konnectivity agent pod count == 0 (cluster=${var.konnectivity_agent.cluster_name}, namespace=${var.konnectivity_agent.namespace}, deployment=${var.konnectivity_agent.deployment_name})"
  combiner     = "OR"
  enabled      = var.konnectivity_agent.enabled
  user_labels = {
    severity = "critical"
  }

  conditions {
    display_name = "Konnectivity agent pod count == 0"

    condition_monitoring_query_language {
      query = <<-EOT
        fetch k8s_container
        | metric 'kubernetes.io/container/uptime'
        | filter (resource.project_id == '${local.konnectivity_agent_project}')
        | filter (resource.cluster_name == '${var.konnectivity_agent.cluster_name}')
        | filter (resource.namespace_name == '${var.konnectivity_agent.namespace}')
        | filter (resource.pod_name =~ '^konnectivity-agent-[^-]+-[^-]+$')
        | filter (resource.container_name != 'konnectivity-agent-metrics-collector')
        | group_by 1m, [row_count: row_count()]
        | every 1m
        | condition val() < 1
      EOT

      duration = "${var.konnectivity_agent.duration_seconds}s"

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = "CRITICAL: Konnectivity agent has zero ready replicas in namespace ${var.konnectivity_agent.namespace}. Investigate immediately."
    mime_type = "text/markdown"
  }

  notification_channels = local.konnectivity_agent_notification_channels

  alert_strategy {
    auto_close           = "${var.konnectivity_agent.auto_close_seconds}s"
    notification_prompts = var.konnectivity_agent.notification_prompts
  }
}
