# Vertex AI consumption and estimated-cost observability.
#
# Vertex AI publishes token counts to Cloud Monitoring but no spend metric, so
# cost is estimated as tokens times list price. The estimate lives here, next to
# the alerts, and is reused verbatim by the dashboard: a single source for the
# expression is what keeps the number on the dashboard and the number that trips
# an alert from drifting apart.
#
# Everything this service reads is a Google Cloud system metric, which is not
# chargeable to ingest and does not consume the metrics free tier. The service
# deliberately creates no log-based and no custom metric, so running it costs
# nothing.

locals {
  vertex_ai_project = var.vertex_ai.project_id != null ? var.vertex_ai.project_id : var.project_id

  vertex_ai_notification_channels = var.vertex_ai.notification_enabled ? (
    length(var.vertex_ai.notification_channels) > 0 ? var.vertex_ai.notification_channels : var.notification_channels
  ) : []

  # Metric names in one place. Every metric under publisher/online_serving is
  # still BETA, so an upstream rename is a single edit here rather than a hunt
  # through the widgets and the alert queries.
  vertex_ai_metrics = {
    token_count         = "aiplatform.googleapis.com/publisher/online_serving/token_count"
    token_throughput    = "aiplatform.googleapis.com/publisher/online_serving/consumed_token_throughput"
    invocation_count    = "aiplatform.googleapis.com/publisher/online_serving/model_invocation_count"
    invocation_latency  = "aiplatform.googleapis.com/publisher/online_serving/model_invocation_latencies"
    first_token_latency = "aiplatform.googleapis.com/publisher/online_serving/first_token_latencies"
  }

  # The resource labels reported by the Monitoring API and the ones listed in
  # the published resource descriptor disagree on how the project is named, so
  # no filter selects it: a dashboard and an alert policy are already scoped to
  # the project that owns them.
  vertex_ai_publisher_resource = "aiplatform.googleapis.com/PublisherModel"

  # Models entering the cost estimate. Only priced models can be estimated;
  # 'models' narrows that set further when a project wants a subset.
  vertex_ai_priced_models = var.vertex_ai.models == null ? sort(keys(var.vertex_ai.pricing)) : sort([
    for model_name in keys(var.vertex_ai.pricing) : model_name
    if contains(var.vertex_ai.models, model_name)
  ])

  # One term per (model, token type, endpoint class) that carries a price.
  # When a model has no regional table, or one identical to its global table,
  # the two classes collapse into a single term with no 'source' selector, which
  # halves the generated expression for the common case.
  vertex_ai_cost_terms_by_model = {
    for model_name in local.vertex_ai_priced_models :
    model_name => (
      var.vertex_ai.pricing[model_name].regional == null ||
      var.vertex_ai.pricing[model_name].regional == var.vertex_ai.pricing[model_name].global
      ? [
        for token_type, price in var.vertex_ai.pricing[model_name].global : {
          model           = model_name
          type            = token_type
          price           = price
          source_selector = ""
        } if price > 0
      ]
      : concat(
        [
          for token_type, price in var.vertex_ai.pricing[model_name].global : {
            model           = model_name
            type            = token_type
            price           = price
            source_selector = ", source=\"global\""
          } if price > 0
        ],
        [
          for token_type, price in var.vertex_ai.pricing[model_name].regional : {
            model           = model_name
            type            = token_type
            price           = price
            source_selector = ", source!=\"global\""
          } if price > 0
        ],
      )
    )
  }

  vertex_ai_cost_terms = flatten(values(local.vertex_ai_cost_terms_by_model))

  # Range-vector windows the cost expression has to be rendered for: the
  # dashboard follows the time-range picker through ${__interval}, each alert
  # threshold pins its own fixed window because ${__interval} has no meaning
  # outside a dashboard widget.
  vertex_ai_cost_windows = toset(concat(
    ["$${__interval}"],
    [for name, threshold in var.vertex_ai.alerts.cost.thresholds : "${threshold.window_seconds}s"],
  ))

  # PromQL is the only generally available way to multiply a series by a price:
  # timeSeriesFilter has no scalar multiplier, timeSeriesFilterRatio only
  # divides two series, and MQL has been deprecated since 2025-07-22.
  #
  # Every term carries 'or on() vector(0)'. A selector that matches no series
  # yields an empty vector, and an empty vector added to a number is empty, so
  # without the fallback a single idle model would blank the whole sum.
  vertex_ai_cost_expressions = {
    for window in local.vertex_ai_cost_windows :
    window => length(local.vertex_ai_cost_terms) == 0 ? "vector(0)" : format("(%s) / 1e6", join(" + ", [
      for term in local.vertex_ai_cost_terms :
      format(
        "(sum(increase({\"%s\", model_user_id=\"%s\", type=\"%s\"%s}[%s])) or on() vector(0)) * %s",
        local.vertex_ai_metrics.token_count, term.model, term.type, term.source_selector, window, term.price,
      )
    ]))
  }

  # Per-model expression, for the cost breakdown chart. Always rendered on the
  # dashboard window.
  vertex_ai_cost_expressions_by_model = {
    for model_name, terms in local.vertex_ai_cost_terms_by_model :
    model_name => format("(%s) / 1e6", join(" + ", [
      for term in terms :
      format(
        "(sum(increase({\"%s\", model_user_id=\"%s\", type=\"%s\"%s}[$${__interval}])) or on() vector(0)) * %s",
        local.vertex_ai_metrics.token_count, term.model, term.type, term.source_selector, term.price,
      )
    ]))
    if length(terms) > 0
  }

  # A threshold materialises only when the service and the cost family are on,
  # at least one model carries a price (an expression that is constantly
  # vector(0) would never fire) and the threshold itself is enabled. The module
  # ships no threshold: the amount is a budget only the consumer knows.
  vertex_ai_cost_alerts = var.vertex_ai.enabled && var.vertex_ai.alerts.cost.enabled && length(local.vertex_ai_cost_terms) > 0 ? {
    for name, threshold in var.vertex_ai.alerts.cost.thresholds :
    name => merge(threshold, {
      channels = threshold.notification_enabled == false ? [] : (
        threshold.notification_channels != null ? threshold.notification_channels : local.vertex_ai_notification_channels
      )
    })
    if threshold.enabled
  } : {}

  vertex_ai_error_rate_enabled = var.vertex_ai.enabled && var.vertex_ai.alerts.error_rate.enabled

  vertex_ai_error_rate_channels = var.vertex_ai.alerts.error_rate.notification_enabled == false ? [] : (
    var.vertex_ai.alerts.error_rate.notification_channels != null ? var.vertex_ai.alerts.error_rate.notification_channels : local.vertex_ai_notification_channels
  )
}

# Alert: Vertex AI estimated cost over a threshold
# One policy per named threshold, so a warning level and a critical level raise
# separate incidents. Several conditions inside a single policy would share the
# combiner and collapse into one incident, which is why they are not used here.
resource "google_monitoring_alert_policy" "vertex_ai_cost" {
  for_each = local.vertex_ai_cost_alerts

  project      = local.vertex_ai_project
  display_name = "Vertex AI estimated cost over ${each.value.threshold_usd} USD (window=${each.value.window_seconds}s, threshold=${each.key})"
  combiner     = "OR"
  enabled      = true
  severity     = each.value.severity

  conditions {
    display_name = "estimated cost > ${each.value.threshold_usd} USD over ${each.value.window_seconds}s"

    condition_prometheus_query_language {
      query               = "${local.vertex_ai_cost_expressions["${each.value.window_seconds}s"]} > ${each.value.threshold_usd}"
      duration            = "${each.value.duration_seconds}s"
      evaluation_interval = "${each.value.evaluation_interval_seconds}s"
    }
  }

  notification_channels = each.value.channels

  alert_strategy {
    auto_close           = "${each.value.auto_close_seconds}s"
    notification_prompts = each.value.notification_prompts
  }
}

# Alert: Vertex AI invocation error rate
# Watches the share of invocations answered with a given response code rather
# than their absolute count, which says nothing without the denominator. The
# ratio and the grouping follow the alert template Google publishes for its own
# Vertex AI dashboard samples.
#
# On Gemini pay-as-you-go a 429 is contention on a shared resource and not an
# exhausted project quota, so this alert dates a degradation; it does not point
# at a quota increase to request. On partner models, which do carry fixed
# per-region quotas, the same signal reads differently.
resource "google_monitoring_alert_policy" "vertex_ai_error_rate" {
  count = local.vertex_ai_error_rate_enabled ? 1 : 0

  project      = local.vertex_ai_project
  display_name = "Vertex AI ${var.vertex_ai.alerts.error_rate.response_code} response rate (project=${local.vertex_ai_project})"
  combiner     = "OR"
  enabled      = true
  severity     = var.vertex_ai.alerts.error_rate.severity

  conditions {
    display_name = "${var.vertex_ai.alerts.error_rate.response_code} share > ${var.vertex_ai.alerts.error_rate.threshold_ratio} per model"

    condition_prometheus_query_language {
      query = join("", [
        "sum by (model_user_id, location)(rate({\"${local.vertex_ai_metrics.invocation_count}\", ",
        "response_code=\"${var.vertex_ai.alerts.error_rate.response_code}\"}",
        "[${var.vertex_ai.alerts.error_rate.window_seconds}s]))",
        " / ",
        "sum by (model_user_id, location)(rate({\"${local.vertex_ai_metrics.invocation_count}\"}",
        "[${var.vertex_ai.alerts.error_rate.window_seconds}s]))",
        " > ${var.vertex_ai.alerts.error_rate.threshold_ratio}",
      ])
      duration            = "${var.vertex_ai.alerts.error_rate.duration_seconds}s"
      evaluation_interval = "${var.vertex_ai.alerts.error_rate.evaluation_interval_seconds}s"
    }
  }

  notification_channels = local.vertex_ai_error_rate_channels

  alert_strategy {
    auto_close           = "${var.vertex_ai.alerts.error_rate.auto_close_seconds}s"
    notification_prompts = var.vertex_ai.alerts.error_rate.notification_prompts
  }
}
