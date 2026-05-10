defmodule MediaCentarr.Profile.Diff do
  @moduledoc """
  Compares two `MediaCentarr.Profile.RunData` snapshots and emits a
  per-metric delta set with classification (ADR-041).

  ## Which metrics are diffed

  Only the metrics most useful for spotting drift are surfaced.
  Picking too many produces alert fatigue; picking too few misses
  real regressions.

    * Microbenchmarks — `median_ns` (typical) and `p99_ns` (tail)
      per scenario per input.
    * Page mounts — `p50_us` and `p95_us` per route.
    * ETS memory — `bytes` per table.

  `ips`, `min`, `max`, and `average` are intentionally excluded —
  they're either derivable, too noisy, or redundant with median /
  p99. Add them later if a real-world miss makes the case.

  ## Classification

  Each delta is classified by `delta_pct` against two thresholds:

      |                            ±0%                           |
      | <-improvement-> | <-stable-> | <-regression-> |
      | (e.g. -25%)     | (-10%..+10%) | (+10%..+25%) | (+25%+) |

  Sign convention: positive `delta_pct` means slower / larger;
  negative means faster / smaller. So `:regression` is positive,
  `:improvement` is negative. Uppercase variants
  (`:REGRESSION`, `:IMPROVEMENT`) signal "big" deltas worth
  highlighting.

  ## Refusals

  Diff returns `{:error, reason}` when comparison is meaningless:

    * `:scale_mismatch` — different `--scale` values produce
      different absolute numbers; cross-scale diff is silent
      noise. Compare like-for-like or not at all.
    * `:schema_mismatch` — different JSON schema versions; we
      can't reliably map fields across versions.
  """

  alias MediaCentarr.Profile.RunData

  @default_threshold_pct 10.0
  @default_big_threshold_pct 25.0

  @type classification ::
          :stable | :improvement | :IMPROVEMENT | :regression | :REGRESSION | :new

  @doc """
  Compares `current` against `baseline`, returning the delta set or
  `{:error, reason}` when comparison is refused.

  ## Options

    * `:threshold_pct` — boundary between `:stable` and
      `:regression`/`:improvement`. Default 10.0.
    * `:big_threshold_pct` — boundary between regression/improvement
      and the highlighted variants. Default 25.0.
  """
  @spec against(%RunData{}, %RunData{}, keyword()) ::
          {:ok, map()} | {:error, atom()}
  def against(%RunData{} = current, %RunData{} = baseline, opts \\ []) do
    with :ok <- check_schema(current, baseline),
         :ok <- check_scale(current, baseline) do
      threshold = Keyword.get(opts, :threshold_pct, @default_threshold_pct)
      big = Keyword.get(opts, :big_threshold_pct, @default_big_threshold_pct)

      metrics =
        Enum.concat([
          microbench_deltas(current.microbenchmarks, baseline.microbenchmarks, threshold, big),
          mount_deltas(current.page_mounts, baseline.page_mounts, threshold, big),
          ets_deltas(current.ets_memory, baseline.ets_memory, threshold, big)
        ])

      {:ok,
       %{
         compared_against: %{
           run_id: baseline.metadata.run_id,
           git_sha: baseline.metadata.git_sha,
           timestamp: baseline.metadata.timestamp
         },
         thresholds: %{stable: threshold, big: big},
         metrics: metrics,
         summary: summarise(metrics)
       }}
    end
  end

  defp check_schema(%{schema_version: a}, %{schema_version: b}) when a == b, do: :ok
  defp check_schema(_, _), do: {:error, :schema_mismatch}

  defp check_scale(%{metadata: %{scale: a}}, %{metadata: %{scale: b}}) when a == b, do: :ok
  defp check_scale(_, _), do: {:error, :scale_mismatch}

  # ---------------------------------------------------------------------------
  # Microbenchmarks
  # ---------------------------------------------------------------------------

  defp microbench_deltas(current, baseline, threshold, big) do
    by_key = fn results ->
      results
      |> Enum.flat_map(fn %{suite: suite, runs: runs} ->
        Enum.flat_map(runs, fn %{input: input, scenarios: scenarios} ->
          Enum.map(scenarios, fn scenario -> {{suite, input, scenario.name}, scenario} end)
        end)
      end)
      |> Map.new()
    end

    cur = by_key.(current)
    base = by_key.(baseline)

    Enum.flat_map(cur, fn {{suite, input, scenario}, current_s} ->
      case Map.fetch(base, {suite, input, scenario}) do
        :error ->
          [
            metric(
              :microbenchmark,
              %{suite: suite, input: input, scenario: scenario},
              :median_ns,
              current_s.stats.median_ns,
              nil,
              threshold,
              big
            ),
            metric(
              :microbenchmark,
              %{suite: suite, input: input, scenario: scenario},
              :p99_ns,
              current_s.stats.p99_ns,
              nil,
              threshold,
              big
            )
          ]

        {:ok, baseline_s} ->
          [
            metric(
              :microbenchmark,
              %{suite: suite, input: input, scenario: scenario},
              :median_ns,
              current_s.stats.median_ns,
              baseline_s.stats.median_ns,
              threshold,
              big
            ),
            metric(
              :microbenchmark,
              %{suite: suite, input: input, scenario: scenario},
              :p99_ns,
              current_s.stats.p99_ns,
              baseline_s.stats.p99_ns,
              threshold,
              big
            )
          ]
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Page mounts
  # ---------------------------------------------------------------------------

  defp mount_deltas(current, baseline, threshold, big) do
    base_by_route = Map.new(baseline, fn r -> {r.route, r} end)

    Enum.flat_map(current, fn cur ->
      base = Map.get(base_by_route, cur.route)

      [
        metric(
          :page_mount,
          %{route: cur.route},
          :p50_us,
          cur.p50_us,
          base && base.p50_us,
          threshold,
          big
        ),
        metric(
          :page_mount,
          %{route: cur.route},
          :p95_us,
          cur.p95_us,
          base && base.p95_us,
          threshold,
          big
        )
      ]
    end)
  end

  # ---------------------------------------------------------------------------
  # ETS memory
  # ---------------------------------------------------------------------------

  defp ets_deltas(current, baseline, threshold, big) do
    base_by_table = Map.new(baseline, fn r -> {r.table, r} end)

    Enum.map(current, fn cur ->
      base = Map.get(base_by_table, cur.table)

      metric(:ets_memory, %{table: cur.table}, :bytes, cur.bytes, base && base.bytes, threshold, big)
    end)
  end

  # ---------------------------------------------------------------------------
  # Per-metric construction
  # ---------------------------------------------------------------------------

  defp metric(category, identifier, metric_name, current, baseline, threshold, big)
       when is_number(current) and is_number(baseline) and baseline > 0 do
    delta_abs = current - baseline
    delta_pct = delta_abs / baseline * 100.0
    classification = classify(delta_pct, threshold, big)

    Map.merge(identifier, %{
      category: category,
      metric: metric_name,
      current: current,
      baseline: baseline,
      delta_abs: delta_abs,
      delta_pct: delta_pct,
      classification: classification
    })
  end

  defp metric(category, identifier, metric_name, current, _baseline, _threshold, _big)
       when is_number(current) do
    Map.merge(identifier, %{
      category: category,
      metric: metric_name,
      current: current,
      baseline: nil,
      delta_abs: nil,
      delta_pct: nil,
      classification: :new
    })
  end

  defp metric(category, identifier, metric_name, _current, _baseline, _threshold, _big) do
    Map.merge(identifier, %{
      category: category,
      metric: metric_name,
      current: nil,
      baseline: nil,
      delta_abs: nil,
      delta_pct: nil,
      classification: :new
    })
  end

  defp classify(delta_pct, threshold, big) do
    cond do
      delta_pct >= big -> :REGRESSION
      delta_pct >= threshold -> :regression
      delta_pct <= -big -> :IMPROVEMENT
      delta_pct <= -threshold -> :improvement
      true -> :stable
    end
  end

  defp summarise(metrics) do
    metrics
    |> Enum.frequencies_by(& &1.classification)
    |> Map.put_new(:stable, 0)
    |> Map.put_new(:improvement, 0)
    |> Map.put_new(:IMPROVEMENT, 0)
    |> Map.put_new(:regression, 0)
    |> Map.put_new(:REGRESSION, 0)
    |> Map.put_new(:new, 0)
    |> Map.put(:total, length(metrics))
  end
end
