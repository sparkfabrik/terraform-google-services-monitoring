# Vertex AI consumption and estimated-cost observability.
#
# Cloud Monitoring carries Vertex AI token counts and no spend metric, so cost is
# estimated as tokens times list price. The expression is built here and reused by
# the dashboard, so both show the same number.
#
# Every metric read is a Google Cloud system metric: not chargeable to ingest and
# outside the metrics free tier. The service creates no log-based and no custom
# metric.

locals {
  vertex_ai_project = var.vertex_ai.project_id != null ? var.vertex_ai.project_id : var.project_id

  # Service-level channels: the service list when set, otherwise the root one.
  vertex_ai_service_channels = length(var.vertex_ai.notification_channels) > 0 ? var.vertex_ai.notification_channels : var.notification_channels

  # Cost-family routing, declared once for every threshold of the family.
  vertex_ai_cost_family_channels = var.vertex_ai.alerts.cost.notification_channels != null ? var.vertex_ai.alerts.cost.notification_channels : local.vertex_ai_service_channels

  # Metric names, in one place. All of them are BETA.
  vertex_ai_metrics = {
    token_count         = "aiplatform.googleapis.com/publisher/online_serving/token_count"
    token_throughput    = "aiplatform.googleapis.com/publisher/online_serving/consumed_token_throughput"
    invocation_count    = "aiplatform.googleapis.com/publisher/online_serving/model_invocation_count"
    invocation_latency  = "aiplatform.googleapis.com/publisher/online_serving/model_invocation_latencies"
    first_token_latency = "aiplatform.googleapis.com/publisher/online_serving/first_token_latencies"
  }

  # Monitored resource of every metric above. Its project label is not filterable:
  # the API and the published descriptor name it differently. Scope comes from the
  # project that owns the dashboard or the policy.
  vertex_ai_publisher_resource = "aiplatform.googleapis.com/PublisherModel"

  # Models entering the cost estimate: the priced ones, narrowed by 'models'.
  vertex_ai_priced_models = var.vertex_ai.models == null ? sort(keys(var.vertex_ai.pricing)) : sort([
    for model_name in keys(var.vertex_ai.pricing) : model_name
    if contains(var.vertex_ai.models, model_name)
  ])

  # Price tables with the assumed cache share folded into 'input'.
  #
  # Models that set cached_input_share report their cache reads inside 'input' and
  # have no cache_read_input series. The share is valued at cache_read_input, the
  # rest at input, and the two collapse into one effective input price;
  # cache_read_input is then dropped so no term queries a missing series. Models
  # that leave the share null keep their table unchanged.
  vertex_ai_effective_pricing = {
    for model_name in local.vertex_ai_priced_models :
    model_name => {
      for class_name, table in {
        global   = var.vertex_ai.pricing[model_name].global
        regional = var.vertex_ai.pricing[model_name].regional
      } :
      class_name => table == null ? null : (
        var.vertex_ai.pricing[model_name].cached_input_share != null &&
        contains(keys(table), "input") && contains(keys(table), "cache_read_input")
        ? {
          # Rounded: the raw product carries a long tail of digits into every
          # occurrence of the price in the generated PromQL.
          for token_type, price in table : token_type => (
            token_type == "input"
            ? tonumber(format("%.6f",
              table["input"] * (1 - var.vertex_ai.pricing[model_name].cached_input_share)
              + table["cache_read_input"] * var.vertex_ai.pricing[model_name].cached_input_share
            ))
            : price
          ) if token_type != "cache_read_input"
        }
        : table
      )
    }
  }

  # One term per (model, token type, endpoint class) priced above zero. A model
  # whose regional table is absent or equal to the global one gets one term per
  # type instead of two.
  #
  # Batch traffic is out of every selector: the metric prefixes its 'source' with
  # 'batch_' and it is billed at a different rate. 'source="global"' excludes
  # "batch_global" on its own.
  vertex_ai_cost_terms_by_model = {
    for model_name in local.vertex_ai_priced_models :
    model_name => (
      local.vertex_ai_effective_pricing[model_name].regional == null ||
      local.vertex_ai_effective_pricing[model_name].regional == local.vertex_ai_effective_pricing[model_name].global
      ? [
        for token_type, price in local.vertex_ai_effective_pricing[model_name].global : {
          model           = model_name
          type            = token_type
          price           = price
          source_selector = ", source!~\"batch_.*\""
        } if price > 0
      ]
      : concat(
        [
          for token_type, price in local.vertex_ai_effective_pricing[model_name].global : {
            model           = model_name
            type            = token_type
            price           = price
            source_selector = ", source=\"global\""
          } if price > 0
        ],
        [
          for token_type, price in local.vertex_ai_effective_pricing[model_name].regional : {
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

  # Windows the cost expression is rendered for: ${__interval} for the dashboard,
  # which follows its time-range picker, plus one fixed window per alert threshold.
  # ${__interval} has no meaning outside a widget.
  vertex_ai_cost_windows = toset(concat(
    ["$${__interval}"],
    [for name, threshold in var.vertex_ai.alerts.cost.thresholds : "${threshold.window_seconds}s"],
  ))

  # PromQL is the only generally available way to multiply a series by a price:
  # timeSeriesFilter has no scalar multiplier, timeSeriesFilterRatio only divides
  # two series, MQL is deprecated since 2025-07-22.
  #
  # 'or on() vector(0)' on every term: a selector matching no series yields an
  # empty vector, and an empty vector added to a number is empty.
  #
  # The input price of a model with cached_input_share is a blend, not a list
  # price, so this figure reads under the invoice whenever the real cached share
  # is below the assumed one. See cached_input_share in variables.tf.
  vertex_ai_cost_expressions = {
    for window in local.vertex_ai_cost_windows :
    window => length(local.vertex_ai_cost_terms) == 0 ? "vector(0)" : format("(%s) / 1e6", join(" + ", [
      for term in local.vertex_ai_cost_terms :
      format(
        "(sum(increase({\"%s\", model_user_id=%s, type=%s%s}[%s])) or on() vector(0)) * %s",
        local.vertex_ai_metrics.token_count, jsonencode(term.model), jsonencode(term.type), term.source_selector, window, term.price,
      )
    ]))
  }

  # Per-model expression for the cost breakdown chart, on the dashboard window.
  vertex_ai_cost_expressions_by_model = {
    for model_name, terms in local.vertex_ai_cost_terms_by_model :
    model_name => format("(%s) / 1e6", join(" + ", [
      for term in terms :
      format(
        "(sum(increase({\"%s\", model_user_id=%s, type=%s%s}[$${__interval}])) or on() vector(0)) * %s",
        local.vertex_ai_metrics.token_count, jsonencode(term.model), jsonencode(term.type), term.source_selector, term.price,
      )
    ]))
    if length(terms) > 0
  }

  # Notification switch per threshold: threshold, then cost family, then service,
  # then on. A nested ternary rather than coalesce(), which is fatal when every
  # argument is null and null is a legal value at each level here.
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

  # Same chain as the cost thresholds, minus the family level: alert, then
  # service, then on. Resolved once and used both to pick the channels and to ask
  # the precondition, so an inherited silence does not fail the check and an
  # alert-level true overrides a service-level false.
  vertex_ai_error_rate_notify = (
    var.vertex_ai.alerts.error_rate.notification_enabled != null
    ? var.vertex_ai.alerts.error_rate.notification_enabled
    : (var.vertex_ai.notification_enabled != null ? var.vertex_ai.notification_enabled : true)
  )

  vertex_ai_error_rate_channels = local.vertex_ai_error_rate_notify ? (
    var.vertex_ai.alerts.error_rate.notification_channels != null ? var.vertex_ai.alerts.error_rate.notification_channels : local.vertex_ai_service_channels
  ) : []
}

# Alert: Vertex AI estimated cost over a threshold.
# One policy per named threshold, so each level raises its own incident;
# conditions sharing a policy would share the combiner and collapse into one.
# Created only when the service, the cost family and the threshold are enabled
# and at least one model is priced.
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

      **This is an estimate, not an invoice.** Vertex AI publishes token counts to Cloud Monitoring but no spend metric, so the figure is tokens multiplied by the published list price, in USD. It ignores committed-use discounts, negotiated rates and credits, and it excludes batch traffic.

      **Part of it rests on an assumption.** Google bills a prompt token served from its implicit context cache at a tenth of the input rate, and the metric folds those tokens into the same `input` type as uncached ones, so they cannot be told apart here. The module works around that by pricing an assumed share of the prompt tokens at the caching rate, which keeps the figure close to the invoice while the assumption holds and makes it read low when the real share drops below it. **This alert can therefore fire late.** The assumed share is stated on the dashboard's first tile; re-measure it against the "Text Input Caching" line of the BigQuery billing export, which is also the authoritative number and lags by about a day.

      A model with traffic but no entry in the module price table contributes nothing here, so real spend can be higher than this alert sees. Compare the "Tokens by model" and "Estimated cost by model" charts on the Vertex AI dashboard: a model in the first and missing from the second has no price configured.

      A stale price table produces a wrong number with no other symptom. Check when it was last reviewed on the dashboard's first tile.
    EOT
  }

  notification_channels = each.value.channels

  alert_strategy {
    auto_close           = "${each.value.auto_close_seconds}s"
    notification_prompts = each.value.prompts
  }

  # An enabled alert with no channel opens incidents nobody is told about.
  # notification_enabled = false is how a check stays silent on purpose.
  lifecycle {
    precondition {
      condition     = each.value.silent || length(each.value.channels) > 0
      error_message = "The Vertex AI cost threshold \"${each.key}\" resolves to no notification channel. Set notification_channels on the threshold, on alerts.cost, on the service or at the module root, or set notification_enabled = false to silence it on purpose."
    }
  }
}

# Alert: Vertex AI invocation error rate.
# Share of invocations answered with a given response code, grouped per model and
# location, evaluated only above min_invocations calls in the window. Ratio and
# grouping follow Google's published sample; the floor does not.
#
# Window and floor move together: a narrower window leaves fewer windows above the
# floor, a lower floor makes single failures significant.
#
# On Gemini pay-as-you-go a 429 is contention on shared capacity, not an exhausted
# project quota. Partner models carry fixed per-region quotas, where it reads
# differently.
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
        "response_code=${jsonencode(var.vertex_ai.alerts.error_rate.response_code)}}",
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
      More than ${var.vertex_ai.alerts.error_rate.threshold_ratio * 100}% of the invocations of one Vertex AI model in one location returned ${var.vertex_ai.alerts.error_rate.response_code}, over a window of ${var.vertex_ai.alerts.error_rate.window_seconds}s in which that model and location took at least ${var.vertex_ai.alerts.error_rate.min_invocations} calls. The grouping and the floor both work on the model and location pair, so a model answering from several regions is watched once per region.

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
      condition     = !local.vertex_ai_error_rate_notify || length(local.vertex_ai_error_rate_channels) > 0
      error_message = "The Vertex AI error-rate alert resolves to no notification channel. Set notification_channels on the alert, on the service or at the module root, or set notification_enabled = false to silence it on purpose."
    }
  }
}
