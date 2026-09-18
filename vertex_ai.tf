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

  # Service-level channels: the service list when set, otherwise the root one.
  vertex_ai_service_channels = length(var.vertex_ai.notification_channels) > 0 ? var.vertex_ai.notification_channels : var.notification_channels

  vertex_ai_notification_channels = var.vertex_ai.notification_enabled ? local.vertex_ai_service_channels : []

  # Cost-family routing, declared once for every threshold of the family.
  vertex_ai_cost_family_channels = var.vertex_ai.alerts.cost.notification_channels != null ? var.vertex_ai.alerts.cost.notification_channels : local.vertex_ai_service_channels

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
  # the two classes collapse into a single term, which halves the generated
  # expression for the common case.
  #
  # Batch traffic is excluded everywhere. The metric reports it with a 'batch_'
  # prefix on 'source' ("batch_global", "batch_<region>"), it is billed at a
  # different rate from online, and without the exclusion it would fall on the
  # wrong side of the global/regional split and be costed at the regional price.
  # 'source="global"' already excludes "batch_global" on its own; the other two
  # selectors need the exclusion written out.
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
          source_selector = ", source!~\"batch_.*\""
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
            source_selector = ", source!=\"global\", source!~\"batch_.*\""
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
  #
  # THIS IS AN UPPER BOUND, NOT A PREDICTION OF THE INVOICE.
  #
  # Google bills a prompt token it served from its implicit context cache at a
  # tenth of the input price, under a separate SKU ("... Text Input Caching").
  # The metric does not make that distinction: for the 'google' publisher the
  # 'type' label only ever takes the values 'input' and 'output', so cache reads
  # are inside 'input' and this expression charges them at the full rate.
  #
  # Nothing in Cloud Monitoring exposes the split. The 'explicit_caching' label
  # on this metric is only populated for the 'anthropic' publisher, and it marks
  # the request rather than separating the tokens inside it. The cache token
  # types this expression does emit for partner models (cache_read_input and the
  # cache_write ones) have no counterpart on Gemini series, so adding such an
  # entry to the price table of a Gemini model produces a term that matches
  # nothing and silently evaluates to zero. Do not try to fix the overestimate
  # that way.
  #
  # Measured against one production invoice, cache reads were about a third of
  # the prompt tokens and the estimate landed roughly 40% above the billed input
  # cost. The direction is guaranteed: the estimate is never below the list-price
  # cost of the same traffic, so a threshold set on it fires early, never late.
  # The authoritative figure remains the BigQuery billing export, where the
  # cached share is a line of its own.
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
  # Most specific wins: threshold, then cost family, then service, then on.
  # Written as a nested ternary rather than coalesce() because coalesce() with
  # every argument null is a fatal error, not a fallback, and a consumer setting
  # notification_enabled = null explicitly at each level is legal on an
  # optional(bool) attribute. That would blow up here with a coalesce error
  # instead of the precondition message written for exactly this case.
  vertex_ai_cost_threshold_notify = {
    for name, threshold in var.vertex_ai.alerts.cost.thresholds :
    name => (
      threshold.notification_enabled != null ? threshold.notification_enabled : (
        var.vertex_ai.alerts.cost.notification_enabled != null ? var.vertex_ai.alerts.cost.notification_enabled : (
          var.vertex_ai.notification_enabled != null ? var.vertex_ai.notification_enabled : true
        )
      )
    )
  }

  vertex_ai_cost_alerts = var.vertex_ai.enabled && var.vertex_ai.alerts.cost.enabled && length(local.vertex_ai_cost_terms) > 0 ? {
    for name, threshold in var.vertex_ai.alerts.cost.thresholds :
    name => merge(threshold, {
      severity = threshold.severity != null ? upper(threshold.severity) : null
      # Resolving to disabled yields an empty list, which is a silent check.
      channels = local.vertex_ai_cost_threshold_notify[name] ? (
        threshold.notification_channels != null ? threshold.notification_channels : local.vertex_ai_cost_family_channels
      ) : []
      prompts = threshold.notification_prompts != null ? threshold.notification_prompts : var.vertex_ai.alerts.cost.notification_prompts
      silent  = local.vertex_ai_cost_threshold_notify[name] == false
    })
    if threshold.enabled
  } : {}

  vertex_ai_error_rate_enabled  = var.vertex_ai.enabled && var.vertex_ai.alerts.error_rate.enabled
  vertex_ai_error_rate_severity = var.vertex_ai.alerts.error_rate.severity != null ? upper(var.vertex_ai.alerts.error_rate.severity) : null

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

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      Estimated Vertex AI spend over the last ${each.value.window_seconds}s crossed ${each.value.threshold_usd} USD.

      **This is an upper bound, not an invoice.** Vertex AI publishes token counts to Cloud Monitoring but no spend metric, so the figure is tokens multiplied by the published list price, in USD. It ignores committed-use discounts, negotiated rates and credits, and it excludes batch traffic.

      **It also charges cached prompt tokens at full price.** Google bills a prompt token served from its implicit context cache at a tenth of the input rate, and the metric folds those tokens into the same `input` type as uncached ones, so they cannot be told apart here. Implicit caching is on by default on recent Gemini models: on a workload where a third of the prompt tokens were cache reads, this figure ran about 40% above the billed input cost. The overshoot is one-directional, so this alert fires early rather than late. The authoritative number is the BigQuery billing export, which is SKU-level, has a line of its own for the cached share, and lags by about a day.

      A model with traffic but no entry in the module price table contributes nothing here, so real spend can be higher than this alert sees. Compare the "Tokens by model" and "Estimated cost by model" charts on the Vertex AI dashboard: a model in the first and missing from the second has no price configured.

      A stale price table produces a wrong number with no other symptom. Check when it was last reviewed on the dashboard's first tile.
    EOT
  }

  notification_channels = each.value.channels

  alert_strategy {
    auto_close           = "${each.value.auto_close_seconds}s"
    notification_prompts = each.value.prompts
  }

  # An enabled alert with nowhere to send opens incidents nobody is told about.
  # Silencing one on purpose is done with notification_enabled, not by leaving
  # the channels empty.
  lifecycle {
    precondition {
      condition     = each.value.silent || length(each.value.channels) > 0
      error_message = "The Vertex AI cost threshold \"${each.key}\" resolves to no notification channel. Set notification_channels on the threshold, on alerts.cost, on the service or at the module root, or set notification_enabled = false to silence it on purpose."
    }
  }
}

# Alert: Vertex AI invocation error rate
# Watches the share of invocations answered with a given response code rather
# than their absolute count, which says nothing without the denominator. The
# ratio and the grouping follow the alert template Google publishes for its own
# Vertex AI dashboard samples; the invocation floor does not, and is there
# because a bare ratio is unusable on a per-model grouping, where a model can
# take single-digit calls in a window.
#
# The defaults trade detection latency for silence: a wide window and a floor
# mean a model with little traffic is not watched at all, which is deliberate.
# Narrowing the window without lowering the floor makes most windows ineligible
# and the alert blind; lowering the floor without widening the window brings
# back the one-failure-out-of-two false positive.
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
  severity     = local.vertex_ai_error_rate_severity

  conditions {
    display_name = "${var.vertex_ai.alerts.error_rate.response_code} share > ${var.vertex_ai.alerts.error_rate.threshold_ratio} per model, over at least ${var.vertex_ai.alerts.error_rate.min_invocations} invocations"

    # The ratio alone is not a signal on a low-traffic model: one failed call out
    # of three reads as 33%. The second clause is the volume floor, and 'and'
    # matches it to the ratio on the same (model_user_id, location) pair, so a
    # model is evaluated only once it has taken enough calls in the window for
    # the percentage to mean something.
    condition_prometheus_query_language {
      query = join("", [
        "sum by (model_user_id, location)(rate({\"${local.vertex_ai_metrics.invocation_count}\", ",
        "response_code=\"${var.vertex_ai.alerts.error_rate.response_code}\"}",
        "[${var.vertex_ai.alerts.error_rate.window_seconds}s]))",
        " / ",
        "sum by (model_user_id, location)(rate({\"${local.vertex_ai_metrics.invocation_count}\"}",
        "[${var.vertex_ai.alerts.error_rate.window_seconds}s]))",
        " > ${var.vertex_ai.alerts.error_rate.threshold_ratio}",
        " and ",
        "sum by (model_user_id, location)(increase({\"${local.vertex_ai_metrics.invocation_count}\"}",
        "[${var.vertex_ai.alerts.error_rate.window_seconds}s]))",
        " >= ${var.vertex_ai.alerts.error_rate.min_invocations}",
      ])
      duration            = "${var.vertex_ai.alerts.error_rate.duration_seconds}s"
      evaluation_interval = "${var.vertex_ai.alerts.error_rate.evaluation_interval_seconds}s"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      More than ${var.vertex_ai.alerts.error_rate.threshold_ratio * 100}% of the invocations of a single Vertex AI model returned ${var.vertex_ai.alerts.error_rate.response_code}, over a window of ${var.vertex_ai.alerts.error_rate.window_seconds}s in which that model took at least ${var.vertex_ai.alerts.error_rate.min_invocations} calls.

      **On a Gemini pay-as-you-go model a 429 is contention on a shared resource, not an exhausted project quota.** Those models have no per-project requests-per-minute limit, so there is no quota increase to request: the alert dates a degradation, it does not point at a fix. The caller should back off and retry.

      **On a partner model the reading is different**: those carry fixed per-region quotas, and a sustained 429 rate there can mean the quota is genuinely exhausted and worth raising.

      A low background rate of 429 is normal on shared capacity, which is what the threshold and the invocation floor are set against. If this alert opens on traffic nobody considers degraded, the threshold is under the resting rate of this workload rather than the workload being unhealthy: measure the resting rate before lowering it further.

      The "Invocations by error category" chart on the Vertex AI dashboard tells contention from an exhausted limit, `capacity` against `user`, **when Vertex populates that label**. It is frequently unset on Gemini traffic, and the chart is then empty; that absence says nothing about the cause.
    EOT
  }

  notification_channels = local.vertex_ai_error_rate_channels

  alert_strategy {
    auto_close           = "${var.vertex_ai.alerts.error_rate.auto_close_seconds}s"
    notification_prompts = var.vertex_ai.alerts.error_rate.notification_prompts
  }

  lifecycle {
    precondition {
      condition     = var.vertex_ai.alerts.error_rate.notification_enabled == false || length(local.vertex_ai_error_rate_channels) > 0
      error_message = "The Vertex AI error-rate alert resolves to no notification channel. Set notification_channels on the alert, on the service or at the module root, or set notification_enabled = false to silence it on purpose."
    }
  }
}
