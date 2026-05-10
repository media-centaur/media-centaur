defmodule MediaCentarr.Profile.DiffTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Profile.{Diff, RunData}

  defp metadata(scale) do
    %{
      run_id: "2026-05-10T15-00-00.000000Z",
      timestamp: ~U[2026-05-10 15:00:00.000000Z],
      scale: scale,
      git_sha: "abc1234",
      git_branch: "main",
      dirty?: false,
      otp_release: "27",
      elixir_version: "1.18.0",
      schedulers: 8,
      cpu_count: 16,
      database_path: "priv/profile/media-centarr.db"
    }
  end

  defp build_run(opts) do
    bench = Keyword.get(opts, :bench, [])
    mounts = Keyword.get(opts, :mounts, [])
    scale = Keyword.get(opts, :scale, :small)

    %{
      RunData.build(metadata(scale), bench, mounts)
      | ets_memory: Keyword.get(opts, :ets_memory, [])
    }
  end

  defp bench(scenario_name, median_ns, p99_ns) do
    [
      %{
        suite: "TestSuite",
        runs: [
          %{
            input: "warm",
            scenarios: [
              %{
                name: scenario_name,
                stats: %{
                  ips: 0,
                  average_ns: median_ns,
                  median_ns: median_ns,
                  p99_ns: p99_ns,
                  min_ns: median_ns,
                  max_ns: median_ns,
                  sample_size: 100
                },
                memory: 0
              }
            ]
          }
        ]
      }
    ]
  end

  defp mount(route, p50_us, p95_us) do
    [
      %{
        route: route,
        warm_cache?: false,
        runs: 30,
        min_us: p50_us,
        p50_us: p50_us,
        p95_us: p95_us,
        max_us: p95_us
      }
    ]
  end

  describe "classification by delta_pct" do
    test "stable when current is within ±10% of baseline" do
      current = build_run(bench: bench("scenario_a", 100, 200))
      baseline = build_run(bench: bench("scenario_a", 105, 200))

      {:ok, deltas} = Diff.against(current, baseline)

      median_metric = Enum.find(deltas.metrics, &(&1.metric == :median_ns))
      assert median_metric.classification == :stable
      assert_in_delta median_metric.delta_pct, -4.76, 0.01
    end

    test "regression when current is +10% to +25% of baseline" do
      current = build_run(bench: bench("scenario_a", 115, 200))
      baseline = build_run(bench: bench("scenario_a", 100, 200))

      {:ok, deltas} = Diff.against(current, baseline)

      median_metric = Enum.find(deltas.metrics, &(&1.metric == :median_ns))
      assert median_metric.classification == :regression
      assert_in_delta median_metric.delta_pct, 15.0, 0.01
    end

    test "REGRESSION when current is +25%+ of baseline" do
      current = build_run(bench: bench("scenario_a", 150, 200))
      baseline = build_run(bench: bench("scenario_a", 100, 200))

      {:ok, deltas} = Diff.against(current, baseline)

      median_metric = Enum.find(deltas.metrics, &(&1.metric == :median_ns))
      assert median_metric.classification == :REGRESSION
    end

    test "improvement when current is -10% to -25% of baseline" do
      current = build_run(bench: bench("scenario_a", 85, 200))
      baseline = build_run(bench: bench("scenario_a", 100, 200))

      {:ok, deltas} = Diff.against(current, baseline)

      median_metric = Enum.find(deltas.metrics, &(&1.metric == :median_ns))
      assert median_metric.classification == :improvement
    end

    test "IMPROVEMENT when current is -25%+ of baseline" do
      current = build_run(bench: bench("scenario_a", 50, 200))
      baseline = build_run(bench: bench("scenario_a", 100, 200))

      {:ok, deltas} = Diff.against(current, baseline)

      median_metric = Enum.find(deltas.metrics, &(&1.metric == :median_ns))
      assert median_metric.classification == :IMPROVEMENT
    end

    test ":new when scenario exists in current but not baseline" do
      current = build_run(bench: bench("scenario_b", 100, 200))
      baseline = build_run(bench: bench("scenario_a", 100, 200))

      {:ok, deltas} = Diff.against(current, baseline)

      new_b = Enum.find(deltas.metrics, &(&1.scenario == "scenario_b" and &1.metric == :median_ns))
      assert new_b.classification == :new
      assert new_b.baseline == nil
    end
  end

  describe "thresholds" do
    test "honour custom :threshold_pct" do
      current = build_run(bench: bench("scenario_a", 103, 200))
      baseline = build_run(bench: bench("scenario_a", 100, 200))

      # Default 10% → stable
      {:ok, default} = Diff.against(current, baseline)
      assert Enum.find(default.metrics, &(&1.metric == :median_ns)).classification == :stable

      # Tightened to 1% → regression
      {:ok, tight} = Diff.against(current, baseline, threshold_pct: 1.0)
      assert Enum.find(tight.metrics, &(&1.metric == :median_ns)).classification == :regression
    end
  end

  describe "refusals" do
    test "{:error, :scale_mismatch} for cross-scale comparison" do
      current = build_run(scale: :small, bench: bench("scenario_a", 100, 200))
      baseline = build_run(scale: :medium, bench: bench("scenario_a", 100, 200))

      assert Diff.against(current, baseline) == {:error, :scale_mismatch}
    end

    test "{:error, :schema_mismatch} for runs with different schema versions" do
      current = build_run(bench: bench("scenario_a", 100, 200))
      baseline = %{build_run(bench: bench("scenario_a", 100, 200)) | schema_version: 0}

      assert Diff.against(current, baseline) == {:error, :schema_mismatch}
    end
  end

  describe "metric coverage" do
    test "includes both median_ns and p99_ns per scenario" do
      current = build_run(bench: bench("a", 100, 500))
      baseline = build_run(bench: bench("a", 100, 500))

      {:ok, deltas} = Diff.against(current, baseline)

      metrics = Enum.map(deltas.metrics, & &1.metric)
      assert :median_ns in metrics
      assert :p99_ns in metrics
    end

    test "includes both p50_us and p95_us per route" do
      current = build_run(mounts: mount("/foo", 1000, 2000))
      baseline = build_run(mounts: mount("/foo", 1000, 2000))

      {:ok, deltas} = Diff.against(current, baseline)

      metrics =
        deltas.metrics
        |> Enum.filter(&(&1.category == :page_mount))
        |> Enum.map(& &1.metric)

      assert :p50_us in metrics
      assert :p95_us in metrics
    end

    test "includes :bytes per ETS table" do
      current = build_run(ets_memory: [%{table: "foo", rows: 10, bytes: 1024}])
      baseline = build_run(ets_memory: [%{table: "foo", rows: 10, bytes: 1024}])

      {:ok, deltas} = Diff.against(current, baseline)

      ets_metric = Enum.find(deltas.metrics, &(&1.category == :ets_memory))
      assert ets_metric.metric == :bytes
      assert ets_metric.classification == :stable
    end
  end

  describe "summary" do
    test "counts each classification across all metrics" do
      current =
        build_run(
          bench:
            bench("regressed", 130, 200) ++
              [
                %{
                  suite: "TestSuite",
                  runs: [
                    %{
                      input: "warm",
                      scenarios: [
                        %{
                          name: "stable",
                          stats: %{
                            ips: 0,
                            average_ns: 100,
                            median_ns: 100,
                            p99_ns: 200,
                            min_ns: 100,
                            max_ns: 100,
                            sample_size: 100
                          },
                          memory: 0
                        }
                      ]
                    }
                  ]
                }
              ]
        )

      baseline =
        build_run(
          bench:
            bench("regressed", 100, 200) ++
              [
                %{
                  suite: "TestSuite",
                  runs: [
                    %{
                      input: "warm",
                      scenarios: [
                        %{
                          name: "stable",
                          stats: %{
                            ips: 0,
                            average_ns: 100,
                            median_ns: 100,
                            p99_ns: 200,
                            min_ns: 100,
                            max_ns: 100,
                            sample_size: 100
                          },
                          memory: 0
                        }
                      ]
                    }
                  ]
                }
              ]
        )

      {:ok, deltas} = Diff.against(current, baseline)

      # 2 metrics per scenario (median + p99) × 2 scenarios = 4
      assert deltas.summary.total == 4
      # "regressed" median goes 100→130 = +30% (REGRESSION); p99 stays 200→200 (stable)
      # "stable" both stay (stable)
      assert Map.get(deltas.summary, :REGRESSION) == 1
      assert deltas.summary.stable == 3
    end
  end
end
