# Vertex AI consumption and estimated-cost Cloud Monitoring dashboard.
#
# One dashboard per project: Vertex AI has no application dimension. Widget set
# follows Google's published sample and adds the estimated cost.
#
# The API normalizes dashboard_json on write, so any value it strips is a
# perpetual plan diff. Rules the JSON here follows: xPos/yPos only when non-zero,
# no empty arrays, objects or strings, no nulls, enums uppercase and never
# zero-valued, no blankView.
#
# No widget declares a timeRange, so all follow the dashboard picker. A
# filter-based widget with an aligner must carry an alignmentPeriod; the console
# widens it as the range grows. Total scorecards set outputFullDuration, which
# collapses the selected window into one value instead of the last point.

locals {
  vertex_ai_dashboard_enabled = var.vertex_ai.enabled && try(var.vertex_ai.dashboard.enabled, false)

  # Cost widgets need both the opt-in and at least one priced model behind them.
  vertex_ai_dashboard_cost = local.vertex_ai_dashboard_enabled && try(var.vertex_ai.dashboard.cost_widgets, false) && length(local.vertex_ai_cost_terms) > 0

  vertex_ai_dashboard_title = try(var.vertex_ai.dashboard.display_name, null) != null ? var.vertex_ai.dashboard.display_name : "Vertex AI consumption and estimated cost (project=${local.vertex_ai_project})"

  # Consumption widgets are never narrowed to the priced models: a model with
  # traffic and no price has to stay visible, it just cannot be costed.
  vertex_ai_token_filter      = "metric.type=\"${local.vertex_ai_metrics.token_count}\" AND resource.type=\"${local.vertex_ai_publisher_resource}\""
  vertex_ai_throughput_filter = "metric.type=\"${local.vertex_ai_metrics.token_throughput}\" AND resource.type=\"${local.vertex_ai_publisher_resource}\""
  vertex_ai_invocation_filter = "metric.type=\"${local.vertex_ai_metrics.invocation_count}\" AND resource.type=\"${local.vertex_ai_publisher_resource}\""
  vertex_ai_latency_filter    = "metric.type=\"${local.vertex_ai_metrics.invocation_latency}\" AND resource.type=\"${local.vertex_ai_publisher_resource}\""
  vertex_ai_ttft_filter       = "metric.type=\"${local.vertex_ai_metrics.first_token_latency}\" AND resource.type=\"${local.vertex_ai_publisher_resource}\""

  # Sentence stating the cache assumption behind the cost figure. One share for
  # every model collapses into a single number; a mixed set names each model.
  vertex_ai_applied_shares = {
    for model_name in local.vertex_ai_priced_models :
    model_name => var.vertex_ai.pricing[model_name].cached_input_share
    if var.vertex_ai.pricing[model_name].cached_input_share != null && var.vertex_ai.pricing[model_name].cached_input_share > 0
  }

  vertex_ai_cache_note = length(local.vertex_ai_applied_shares) == 0 ? join(" ", [
    "No cache correction is applied, so this is an **upper bound**:",
    "cached prompt tokens are charged at the full input rate.",
    ]) : (
    length(distinct(values(local.vertex_ai_applied_shares))) == 1 ? join(" ", [
      "**Corrected with an assumption:** ${format("%.0f", values(local.vertex_ai_applied_shares)[0] * 100)}% of prompt tokens are taken to be cache reads",
      "and priced at the caching rate, on ${length(local.vertex_ai_applied_shares)} of the priced models.",
      "If the real share is lower than that, this figure reads **under** the invoice.",
      ]) : join(" ", [
      "**Corrected with a per-model assumption** on the cached share:",
      join(", ", [for m, s in local.vertex_ai_applied_shares : "${m} ${format("%.0f", s * 100)}%"]),
      ". Where the real share is lower, this figure reads **under** the invoice.",
    ])
  )

  vertex_ai_dashboard_widgets = {
    # Text widget: the Widget object has only a title and no description field.
    # Created with the cost tiles it explains, above them.
    cost_note = {
      title = "How to read the estimated cost"
      text = {
        format = "MARKDOWN"
        content = join(" ", [
          "**The cost figures below are an estimate at list price, not an invoice.**",
          "They are token counts multiplied by the published list price, in USD. Price table last checked on **${var.vertex_ai.pricing_verified_on}**.",
          local.vertex_ai_cache_note,
          "The reason an assumption is needed at all: Google bills a prompt token served from its implicit cache at a tenth of the input price, but Cloud Monitoring reports cached and uncached prompt tokens under the same `input` type and offers no way to separate them.",
          "List prices also carry no committed-use discount, no negotiated rate and no credit, and batch traffic is left out entirely because it is billed at a different rate.",
          "A model with traffic but no entry in the price table shows up in the token widgets and contributes nothing here.",
          "**For the amount actually billed, and for the cached share as its own line, use the BigQuery billing export**, which is SKU-level and lags by about a day. That is also where the assumed share should be re-measured.",
        ])
      }
    }

    cost_scorecard = {
      title = "Estimated cost, selected window (USD, list price)"
      scorecard = {
        timeSeriesQuery = {
          prometheusQuery    = local.vertex_ai_cost_expressions["$${__interval}"]
          outputFullDuration = true
        }
      }
    }

    input_tokens_scorecard = {
      title = "Input tokens, selected window"
      scorecard = {
        timeSeriesQuery = {
          timeSeriesFilter = {
            filter = "${local.vertex_ai_token_filter} AND metric.labels.type=\"input\""
            aggregation = {
              alignmentPeriod    = "60s"
              perSeriesAligner   = "ALIGN_SUM"
              crossSeriesReducer = "REDUCE_SUM"
            }
          }
          outputFullDuration = true
        }
      }
    }

    output_tokens_scorecard = {
      title = "Output tokens, selected window"
      scorecard = {
        timeSeriesQuery = {
          timeSeriesFilter = {
            filter = "${local.vertex_ai_token_filter} AND metric.labels.type=\"output\""
            aggregation = {
              alignmentPeriod    = "60s"
              perSeriesAligner   = "ALIGN_SUM"
              crossSeriesReducer = "REDUCE_SUM"
            }
          }
          outputFullDuration = true
        }
      }
    }

    invocations_scorecard = {
      title = "Model invocations, selected window"
      scorecard = {
        timeSeriesQuery = {
          timeSeriesFilter = {
            filter = local.vertex_ai_invocation_filter
            aggregation = {
              alignmentPeriod    = "60s"
              perSeriesAligner   = "ALIGN_SUM"
              crossSeriesReducer = "REDUCE_SUM"
            }
          }
          outputFullDuration = true
        }
      }
    }

    # One dataSet per priced model, each carrying that model's own price terms.
    cost_by_model_chart = {
      title = "Estimated cost by model (USD, list price)"
      xyChart = {
        dataSets = [
          for model_name in sort(keys(local.vertex_ai_cost_expressions_by_model)) : {
            plotType       = "STACKED_BAR"
            targetAxis     = "Y1"
            legendTemplate = model_name
            timeSeriesQuery = {
              prometheusQuery = local.vertex_ai_cost_expressions_by_model[model_name]
            }
          }
        ]
        yAxis = { label = "USD", scale = "LINEAR" }
      }
    }

    tokens_by_model_chart = {
      title = "Tokens by model"
      xyChart = {
        dataSets = [{
          plotType   = "STACKED_BAR"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = local.vertex_ai_token_filter
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_SUM"
                crossSeriesReducer = "REDUCE_SUM"
                groupByFields      = ["resource.label.model_user_id"]
              }
            }
          }
        }]
        yAxis = { label = "tokens", scale = "LINEAR" }
      }
    }

    # Model and token type on separate charts: grouping by both gives around
    # thirty series, past the point where adjacent colours are tellable apart.
    tokens_by_type_chart = {
      title = "Tokens by type"
      xyChart = {
        dataSets = [{
          plotType   = "STACKED_BAR"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = local.vertex_ai_token_filter
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_SUM"
                crossSeriesReducer = "REDUCE_SUM"
                groupByFields      = ["metric.label.type"]
              }
            }
          }
        }]
        yAxis = { label = "tokens", scale = "LINEAR" }
      }
    }

    # consumed_token_throughput is burndown-weighted and drives quota accounting;
    # token_count above is the raw count. Different quantities, separate widgets.
    throughput_chart = {
      title = "Consumed token throughput by model"
      xyChart = {
        dataSets = [{
          plotType   = "LINE"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = local.vertex_ai_throughput_filter
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_RATE"
                crossSeriesReducer = "REDUCE_SUM"
                groupByFields      = ["resource.label.model_user_id"]
              }
            }
          }
        }]
        yAxis = { label = "tokens/s", scale = "LINEAR" }
      }
    }

    qps_chart = {
      title = "Invocations per second by model"
      xyChart = {
        dataSets = [{
          plotType   = "LINE"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = local.vertex_ai_invocation_filter
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_RATE"
                crossSeriesReducer = "REDUCE_SUM"
                groupByFields      = ["resource.label.model_user_id"]
              }
            }
          }
        }]
        yAxis = { label = "requests/s", scale = "LINEAR" }
      }
    }

    response_code_chart = {
      title = "Invocations by response code"
      xyChart = {
        dataSets = [{
          plotType   = "LINE"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = local.vertex_ai_invocation_filter
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_RATE"
                crossSeriesReducer = "REDUCE_SUM"
                groupByFields      = ["metric.label.response_code"]
              }
            }
          }
        }]
        yAxis = { label = "requests/s", scale = "LINEAR" }
      }
    }

    # error_category tells contention from an exhausted quota. Vertex leaves the
    # label unset on much of the traffic, Gemini 429s included, so this chart is
    # often empty; the response-code chart beside it always has data.
    error_category_chart = {
      title = "Invocations by error category (label often unset)"
      xyChart = {
        dataSets = [{
          plotType   = "LINE"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = local.vertex_ai_invocation_filter
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_RATE"
                crossSeriesReducer = "REDUCE_SUM"
                groupByFields      = ["metric.label.error_category"]
              }
            }
          }
        }]
        yAxis = { label = "requests/s", scale = "LINEAR" }
      }
    }

    latency_p50_chart = {
      title = "Invocation latency p50 per model"
      xyChart = {
        dataSets = [{
          plotType   = "LINE"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = "${local.vertex_ai_latency_filter} AND metric.labels.latency_type=\"total\""
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_DELTA"
                crossSeriesReducer = "REDUCE_PERCENTILE_50"
                groupByFields      = ["resource.label.model_user_id"]
              }
            }
          }
        }]
        yAxis = { label = "ms", scale = "LINEAR" }
      }
    }

    # One percentile per chart: both together would be twelve lines on six colours.
    #
    # The percentile comes from the cross-series reducer, not the aligner. These
    # are DISTRIBUTION metrics split across latency_type and token-size buckets:
    # ALIGN_DELTA merges the distributions and REDUCE_PERCENTILE_* reads the
    # percentile off the merged one. latency_type is pinned to "total", the
    # latency the caller waits; "model" and "overhead" are its components.
    latency_p95_chart = {
      title = "Invocation latency p95 per model"
      xyChart = {
        dataSets = [{
          plotType   = "LINE"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = "${local.vertex_ai_latency_filter} AND metric.labels.latency_type=\"total\""
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_DELTA"
                crossSeriesReducer = "REDUCE_PERCENTILE_95"
                groupByFields      = ["resource.label.model_user_id"]
              }
            }
          }
        }]
        yAxis = { label = "ms", scale = "LINEAR" }
      }
    }

    ttft_chart = {
      title = "First token latency p50 per model"
      xyChart = {
        dataSets = [{
          plotType   = "LINE"
          targetAxis = "Y1"
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = local.vertex_ai_ttft_filter
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_DELTA"
                crossSeriesReducer = "REDUCE_PERCENTILE_50"
                groupByFields      = ["resource.label.model_user_id"]
              }
            }
          }
        }]
        yAxis = { label = "ms", scale = "LINEAR" }
      }
    }

    # No cache-share tile. It could only read 'cache_read_input', which exists on
    # partner-model series alone and is zero unless the caller drives Anthropic
    # prompt caching; Gemini cache reads sit inside 'input'. The cached share is
    # in the BigQuery billing export, on the "Text Input Caching" SKU.
  }

  # Rows assembled first, then flattened into positioned tiles. Empty rows are
  # dropped so the rest reflow. Optional tiles use a filtered for-expression: a
  # ternary between a one-tile tuple and an empty one does not type-check.
  # Scorecard width follows the tile count: four tiles with the cost one, three
  # without. A fixed 12 would leave a quarter of the row empty in the second case.
  vertex_ai_dashboard_scorecard_width = local.vertex_ai_dashboard_cost ? 12 : 16

  vertex_ai_dashboard_rows = [
    for row in [
      [for widget in [local.vertex_ai_dashboard_widgets.cost_note] : { width = 48, height = 4, widget = widget } if local.vertex_ai_dashboard_cost],
      concat(
        [for widget in [local.vertex_ai_dashboard_widgets.cost_scorecard] : { width = local.vertex_ai_dashboard_scorecard_width, height = 8, widget = widget } if local.vertex_ai_dashboard_cost],
        [
          { width = local.vertex_ai_dashboard_scorecard_width, height = 8, widget = local.vertex_ai_dashboard_widgets.input_tokens_scorecard },
          { width = local.vertex_ai_dashboard_scorecard_width, height = 8, widget = local.vertex_ai_dashboard_widgets.output_tokens_scorecard },
          { width = local.vertex_ai_dashboard_scorecard_width, height = 8, widget = local.vertex_ai_dashboard_widgets.invocations_scorecard },
        ],
      ),
      [for widget in [local.vertex_ai_dashboard_widgets.cost_by_model_chart] : { width = 48, height = 16, widget = widget } if local.vertex_ai_dashboard_cost],
      [
        { width = 24, height = 16, widget = local.vertex_ai_dashboard_widgets.tokens_by_model_chart },
        { width = 24, height = 16, widget = local.vertex_ai_dashboard_widgets.tokens_by_type_chart },
      ],
      [
        { width = 24, height = 16, widget = local.vertex_ai_dashboard_widgets.throughput_chart },
        { width = 24, height = 16, widget = local.vertex_ai_dashboard_widgets.qps_chart },
      ],
      [
        { width = 24, height = 16, widget = local.vertex_ai_dashboard_widgets.response_code_chart },
        { width = 24, height = 16, widget = local.vertex_ai_dashboard_widgets.error_category_chart },
      ],
      [
        { width = 24, height = 16, widget = local.vertex_ai_dashboard_widgets.latency_p50_chart },
        { width = 24, height = 16, widget = local.vertex_ai_dashboard_widgets.latency_p95_chart },
      ],
      [
        { width = 48, height = 16, widget = local.vertex_ai_dashboard_widgets.ttft_chart },
      ],
    ] : row if length(row) > 0
  ]

  vertex_ai_dashboard_row_heights = [
    for row in local.vertex_ai_dashboard_rows : max([for tile in row : tile.height]...)
  ]

  # xPos/yPos are attached via merge() only when non-zero: the API strips zero
  # positions, so emitting them would cause a perpetual plan diff.
  vertex_ai_dashboard_tiles = flatten([
    for row_index, row in local.vertex_ai_dashboard_rows : [
      for tile_index, tile in row : merge(
        { width = tile.width, height = tile.height, widget = tile.widget },
        { for k, v in { xPos = tile_index == 0 ? 0 : sum(slice([for t in row : t.width], 0, tile_index)) } : k => v if v > 0 },
        { for k, v in { yPos = row_index == 0 ? 0 : sum(slice(local.vertex_ai_dashboard_row_heights, 0, row_index)) } : k => v if v > 0 },
      )
    ]
  ])
}

# Dashboard: Vertex AI consumption and estimated cost.
# displayName is not the resource identity, so a title change is an in-place
# update.
resource "google_monitoring_dashboard" "vertex_ai" {
  count = local.vertex_ai_dashboard_enabled ? 1 : 0

  project = local.vertex_ai_project
  dashboard_json = jsonencode({
    displayName = local.vertex_ai_dashboard_title
    mosaicLayout = {
      columns = 48
      tiles   = local.vertex_ai_dashboard_tiles
    }
  })
}
