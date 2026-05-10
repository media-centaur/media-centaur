defmodule MediaCentarr.Profile.ReporterTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Profile.Reporter

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

  describe "write/4" do
    test "produces a markdown file with all top-level sections" do
      path = Reporter.write(metadata(), bench_results(), mount_results(), runs_dir: @tmp_dir)
      assert File.exists?(path)
      body = File.read!(path)

      # Stable section headings — the diff-meaningfulness contract.
      assert body =~ "# Media Centarr Profile Run"
      assert body =~ "## Environment"
      assert body =~ "## Microbenchmarks"
      assert body =~ "### Library.Views.ContinueWatching"
      assert body =~ "## Page Mount Timing"
      assert body =~ "## ETS Memory"
      assert body =~ "## Notes"

      # Header carries the metadata
      assert body =~ "abc1234"
      assert body =~ "main"
      assert body =~ "small"

      # latest.md symlink
      latest = Path.join(@tmp_dir, "latest.md")
      assert File.read_link(latest) == {:ok, Path.basename(path)}
    end

    test "handles empty bench and mount results without crashing" do
      path = Reporter.write(metadata(), [], [], runs_dir: @tmp_dir)
      body = File.read!(path)

      # Empty paths still produce well-formed sections with placeholders.
      assert body =~ "## Microbenchmarks"
      assert body =~ "no suites discovered"
      assert body =~ "## Page Mount Timing"
      assert body =~ "no routes measured"
    end
  end
end
