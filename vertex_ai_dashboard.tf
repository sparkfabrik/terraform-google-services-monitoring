# Vertex AI consumption and estimated-cost Cloud Monitoring dashboard.
#
# One dashboard per project. Vertex AI has no application dimension, so the
# per-app dashboard shape used by the Typesense service does not apply here.
#
# The widget set follows the dashboard Google publishes for its own Vertex AI
# integration (invocations, latencies, response codes, throughput, token counts)
# and adds what that one does not carry: the estimated cost, the cache token
# split, and the share of input served from cache.
#
# Drift-safe JSON authoring (the Cloud Monitoring API normalizes dashboard_json
# on write, so any value it strips becomes a perpetual plan diff): xPos/yPos keys
# are attached only when non-zero, no empty arrays/objects/strings, no nulls,
# enums uppercase and never zero-valued, no blankView.
#
# Time-range behaviour: no widget declares its own timeRange, so every one of
# them follows the dashboard picker. Filter-based widgets must carry an
# alignmentPeriod whenever an aligner is set (the API rejects the pair
# otherwise); the console widens it on its own as the selected range grows.
# Scorecards that show a total set outputFullDuration so the whole selected
# window collapses into one value instead of the last aligned point.

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

  vertex_ai_dashboard_widgets = {
    # The Widget object has no description field, only a title, so the caveat
    # that makes the two cost tiles readable has to be its own text widget.
    # It sits above them and is created only when they are.
    cost_note = {
      title = "How to read the estimated cost"
      text = {
        format = "MARKDOWN"
        content = join(" ", [
          "**The cost figures below are an upper bound at list price, not an invoice.**",
          "They are token counts multiplied by the published list price, in USD. Price table last checked on **${var.vertex_ai.pricing_verified_on}**.",
          "**They read high whenever context caching is working.**",
          "Google bills a prompt token it served from its implicit cache at a tenth of the input price, but Cloud Monitoring reports cached and uncached prompt tokens under the same `input` type, so this dashboard charges all of them at the full rate and cannot tell them apart.",
          "Implicit caching is on by default on recent Gemini models: where a third of the prompt tokens are cache reads, expect this figure to sit roughly 40% above the billed input cost.",
          "The error is one-directional, so the real cost is never higher than what you see here for the traffic counted.",
          "List prices also carry no committed-use discount, no negotiated rate and no credit, and batch traffic is left out entirely because it is billed at a different rate.",
          "A model with traffic but no entry in the price table shows up in the token widgets and contributes nothing here.",
          "**For the amount actually billed, and for the cached share as its own line, use the BigQuery billing export**, which is SKU-level and lags by about a day.",
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

    # Split by model and by token type on separate charts rather than on one
    # grouped by both: six models times five token types is around thirty series,
    # far past the point where adjacent colours stop being tellable apart.
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

    # consumed_token_throughput is burndown-weighted and is the figure quota
    # accounting uses; token_count above is the raw count. They measure different
    # quantities and are deliberately kept in separate widgets.
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

    # error_category separates contention on a shared resource from a quota the
    # caller actually exhausted, which is the difference between a 429 you can
    # act on and one you cannot.
    #
    # Vertex leaves the label unset on a good share of real traffic, Gemini 429s
    # included, and the chart is then empty. That is why the error-rate alert
    # points at it as a hint rather than as the diagnosis, and why an empty chart
    # here must not be read as "no errors": the response-code chart beside it is
    # the one that always has data.
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

    # One percentile per chart. Both on one chart would put twelve lines on six
    # colours, and a static legendTemplate would label every line of a dataset
    # "p50", losing the model name that identifies it.
    #
    # The percentile is taken by the cross-series reducer, not by the aligner:
    # these are DISTRIBUTION metrics split across latency_type and token-size
    # buckets, so aligning each series to its own percentile and then averaging
    # would produce a number no request ever had. ALIGN_DELTA merges the
    # distributions first and REDUCE_PERCENTILE_* reads the percentile off the
    # merged one. The filter pins latency_type to "total", the latency the
    # caller actually waits; "model" and "overhead" are its two components.
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

    # There is deliberately no "share of prompt tokens served from cache" tile.
    # It would have to read the 'cache_read_input' token type, which exists only
    # on partner-model series and is zero unless the caller drives Anthropic
    # prompt caching explicitly. Gemini's implicit cache reads never appear under
    # any cache type: they are inside 'input'. A tile built that way therefore
    # reads a steady 0% precisely when caching is working hardest, which is worse
    # than showing nothing, and it was removed for that reason. The cached share
    # is visible in the BigQuery billing export, on the "Text Input Caching" SKU.
  }

  # Rows are assembled first, then flattened into positioned tiles. Empty rows
  # are dropped so the remaining tiles reflow instead of leaving a gap.
  #
  # Optional tiles are selected with a filtered for-expression rather than a
  # conditional between two tuples: Terraform requires both arms of a ternary to
  # carry the same type, and a one-tile tuple is not the same type as an empty
  # one, so the ternary form fails to evaluate.
  # The scorecard row holds four tiles with the cost one and three without, so
  # the width has to follow: leaving it at 12 would end the row at 36 of the 48
  # columns and leave a quarter of the row empty whenever cost_widgets is off.
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

# Dashboard: Vertex AI consumption and estimated cost
# displayName is not the resource identity: title changes, display_name
# overrides included, are in-place updates.
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
