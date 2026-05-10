defmodule MediaCentarr.Profile.ReporterTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Profile.{JSONFormatter, Reporter, RunData}

  @tmp_dir Path.join(System.tmp_dir!(), "media_centarr_profile_reporter_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  defp metadata do
    %{
      run_id: "2026-05-10T15-00-00.000000Z",
      timestamp: ~U[2026-05-10 15:00:00.000000Z],
      scale: :small,
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

  defp bench_results do
    [
      %{
        suite: "Library.Views.ContinueWatching",
        runs: [
          %{
            input: "warm-cache",
            scenarios: [
              %{
                name: "Views.continue_watching/1",
                stats: %{
                  ips: 1_500_000.0,
                  average_ns: 666.0,
                  median_ns: 600.0,
                  p99_ns: 1200.0,
                  min_ns: 400.0,
                  max_ns: 2000.0,
                  sample_size: 100_000
                },
                memory: 1024
              }
            ]
          }
        ]
      }
    ]
  end

  defp mount_results do
    [
      %{route: "/", warm_cache?: true, runs: 30, min_us: 4120, p50_us: 4580, p95_us: 6310, max_us: 8990}
    ]
  end

  defp run_data do
    RunData.build(metadata(), bench_results(), mount_results())
  end

  describe "write/2" do
    test "produces both markdown and JSON files with stable structure" do
      %{markdown: md_path, json: json_path} = Reporter.write(run_data(), runs_dir: @tmp_dir)

      assert File.exists?(md_path)
      assert File.exists?(json_path)

      md_body = File.read!(md_path)

      # Stable section headings — the diff-meaningfulness contract.
      assert md_body =~ "# Media Centarr Profile Run"
      assert md_body =~ "## Environment"
      assert md_body =~ "## Microbenchmarks"
      assert md_body =~ "### Library.Views.ContinueWatching"
      assert md_body =~ "## Page Mount Timing"
      assert md_body =~ "## Notes"

      # Header carries the metadata
      assert md_body =~ "abc1234"
      assert md_body =~ "main"
      assert md_body =~ "small"

      # JSON file is valid and round-trips through the decoder
      json_body = File.read!(json_path)
      {:ok, decoded} = JSONFormatter.decode(json_body)
      assert decoded.metadata.git_sha == "abc1234"
      assert decoded.metadata.scale == "small"
      assert decoded.deltas == nil

      # latest.md / latest.json symlinks
      assert File.read_link(Path.join(@tmp_dir, "latest.md")) ==
               {:ok, Path.basename(md_path)}

      assert File.read_link(Path.join(@tmp_dir, "latest.json")) ==
               {:ok, Path.basename(json_path)}
    end

    test "handles empty bench and mount results without crashing" do
      empty_run = RunData.build(metadata(), [], [])
      %{markdown: md_path} = Reporter.write(empty_run, runs_dir: @tmp_dir)

      body = File.read!(md_path)
      assert body =~ "no suites discovered"
      assert body =~ "no routes measured"
    end
  end

  describe "baseline_json_path/1" do
    test "returns :none when no baseline file exists for the scale" do
      assert Reporter.baseline_json_path(:nonexistent_scale) == :none
    end
  end
end
