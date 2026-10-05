locals {
  cloud_armor_adaptive_protection_project = (
    var.cloud_armor_adaptive_protection.project_id != null
    ? var.cloud_armor_adaptive_protection.project_id
    : var.project_id
  )

  cloud_armor_adaptive_protection_notification_channels = (
    var.cloud_armor_adaptive_protection.notification_enabled
    ? (
      length(var.cloud_armor_adaptive_protection.notification_channels) > 0
      ? var.cloud_armor_adaptive_protection.notification_channels
      : var.notification_channels
    )
    : []
  )

  cloud_armor_adaptive_protection_policies = toset(var.cloud_armor_adaptive_protection.security_policies)

  # Adaptive Protection only emits alerts for policies where layer 7 DDoS
  # defense is enabled, so an alert on any other policy would never fire.
  cloud_armor_adaptive_protection_verify = (
    var.cloud_armor_adaptive_protection.enabled
    && var.cloud_armor_adaptive_protection.verify_adaptive_protection_enabled
  )

  cloud_armor_adaptive_protection_disabled_policies = [
    for name in local.cloud_armor_adaptive_protection_policies : name
    if !try(data.google_compute_security_policy.cloud_armor_adaptive_protection[name].adaptive_protection_config[0].layer_7_ddos_defense_config[0].enable, false)
  ]

  cloud_armor_adaptive_protection_filter = join("\n", [
    "logName=\"projects/${local.cloud_armor_adaptive_protection_project}/logs/networksecurity.googleapis.com%2Fdos_attack\"",
    "AND resource.type=\"network_security_policy\"",
    "AND resource.labels.policy_name=(${join(" OR ", [for name in sort(tolist(local.cloud_armor_adaptive_protection_policies)) : "\"${name}\""])})",
  ])
}

# Reads each monitored security policy to verify that Adaptive Protection
# (layer 7 DDoS defense) is enabled on it before the alert is created.
data "google_compute_security_policy" "cloud_armor_adaptive_protection" {
  for_each = local.cloud_armor_adaptive_protection_verify ? local.cloud_armor_adaptive_protection_policies : toset([])

  project = local.cloud_armor_adaptive_protection_project
  name    = each.value
}

# Notifies every Adaptive Protection attack detection on the monitored Cloud
# Armor security policies, read from the dos_attack log Adaptive Protection
# writes for each alert.
resource "google_monitoring_alert_policy" "cloud_armor_adaptive_protection" {
  count = var.cloud_armor_adaptive_protection.enabled ? 1 : 0

  project      = local.cloud_armor_adaptive_protection_project
  display_name = "Cloud Armor Adaptive Protection: attack detected"
  combiner     = "OR"
  severity     = var.cloud_armor_adaptive_protection.severity
  user_labels  = var.cloud_armor_adaptive_protection.user_labels

  conditions {
    display_name = "Adaptive Protection alert on ${join(", ", sort(tolist(local.cloud_armor_adaptive_protection_policies)))}"

    condition_matched_log {
      filter = local.cloud_armor_adaptive_protection_filter

      label_extractors = {
        "security_policy" = "EXTRACT(resource.labels.policy_name)"
        "backend_service" = "EXTRACT(jsonPayload.backendService)"
        "confidence"      = "EXTRACT(jsonPayload.confidence)"
        "attack_size"     = "EXTRACT(jsonPayload.attackSize)"
      }
    }
  }

  documentation {
    content   = "Cloud Armor Adaptive Protection detected a likely layer 7 DDoS attack against backend service `$${log.extracted_label.backend_service}` protected by security policy `$${log.extracted_label.security_policy}` (confidence `$${log.extracted_label.confidence}`, attack size `$${log.extracted_label.attack_size}` requests per second). On Cloud Armor Standard the alert is basic: it carries no attack signature and no suggested rule, which only Cloud Armor Enterprise provides. Open the Adaptive Protection dashboard of the policy in the Cloud Armor console and the `networksecurity.googleapis.com/dos_attack` log for the alert details, then check the load balancer logs of that backend for the top sources, paths and user agents. If the traffic is an attack, block it with a targeted rule or a tighter rate limit; if it is a legitimate spike (a campaign, a deadline), no action is needed."
    mime_type = "text/markdown"
  }

  notification_channels = local.cloud_armor_adaptive_protection_notification_channels

  alert_strategy {
    auto_close = "${var.cloud_armor_adaptive_protection.auto_close_seconds}s"

    notification_rate_limit {
      period = "${var.cloud_armor_adaptive_protection.notification_rate_limit_seconds}s"
    }
  }

  lifecycle {
    precondition {
      condition     = !local.cloud_armor_adaptive_protection_verify || length(local.cloud_armor_adaptive_protection_disabled_policies) == 0
      error_message = "Adaptive Protection (layer 7 DDoS defense) is not enabled on these security policies, so they would never raise an alert: ${join(", ", local.cloud_armor_adaptive_protection_disabled_policies)}. Enable it on the policy (layer_7_ddos_defense_enable = true in the cloud-armor module), or set verify_adaptive_protection_enabled = false when the policy is created in the same apply."
    }
  }
}
