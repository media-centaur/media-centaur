defmodule MediaCentaur.Watcher.ScanStatsTest do
  # async: false — exercises the application-wide ScanStats singleton via the
  # real scan telemetry event. Per-test isolation comes from a unique dir key,
  # so concurrent suites never collide on the same row.
  use ExUnit.Case, async: false

  alias MediaCentaur.Watcher.ScanStats

  defp unique_dir, do: "/tmp/scan_stats_test_#{:erlang.unique_integer([:positive])}"

  defp emit_scan(dir, opts) do
    :telemetry.execute(
      [:media_centaur, :watcher, :scan, :stop],
      %{duration: Keyword.get(opts, :duration, 1_000)},
      %{
        dir: dir,
        total_video_files: Keyword.fetch!(opts, :total),
        known: Keyword.get(opts, :known, 0),
        dispatched: Keyword.fetch!(opts, :dispatched),
        relinked: Keyword.get(opts, :relinked, 0)
      }
    )

    # all/0 is a GenServer.call; the telemetry handler ran synchronously in this
    # process and cast to the singleton before this read is enqueued, so FIFO
    # ordering guarantees the record is visible without sleeping.
    ScanStats.all()
  end

  describe "last_scan/1" do
    test "returns nil for a dir that has never been scanned" do
      assert ScanStats.last_scan(unique_dir()) == nil
    end

    test "retains the scan summary for a dir after a scan telemetry event" do
      dir = unique_dir()
      emit_scan(dir, total: 1_432, dispatched: 3, relinked: 1)

      summary = ScanStats.last_scan(dir)
      assert summary.total == 1_432
      assert summary.new == 3
      assert summary.relinked == 1
      assert %DateTime{} = summary.at
    end

    test "keeps only the newest scan per dir" do
      dir = unique_dir()
      emit_scan(dir, total: 10, dispatched: 10)
      emit_scan(dir, total: 12, dispatched: 2)

      summary = ScanStats.last_scan(dir)
      assert summary.total == 12
      assert summary.new == 2
    end
  end

  describe "resilience when the server is down" do
    # The Status page reads these on every render. ScanStats lives under the
    # watcher's :one_for_all tree, so a sibling crash briefly takes it down —
    # a bare GenServer.call would then crash the drill-in render. Reads must
    # degrade to empty instead, mirroring Supervisor.statuses/0's try/catch.
    test "all/0 returns an empty map when the server is not running" do
      assert ScanStats.all(:scan_stats_definitely_not_started) == %{}
    end

    test "last_scan/1 returns nil when the server is not running" do
      assert ScanStats.last_scan("/whatever", :scan_stats_definitely_not_started) == nil
    end
  end

  describe "all/0" do
    test "includes every scanned dir, keyed by dir" do
      dir_a = unique_dir()
      dir_b = unique_dir()
      emit_scan(dir_a, total: 5, dispatched: 5)
      all = emit_scan(dir_b, total: 8, dispatched: 1)

      assert all[dir_a].total == 5
      assert all[dir_b].total == 8
    end
  end
end
