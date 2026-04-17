defmodule MediaCentarr.Pipeline.Image.StatsTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Pipeline.Image.Stats

  setup do
    name = :"image_stats_#{System.unique_integer([:positive])}"
    stats = start_supervised!({Stats, name: name})
    {:ok, stats: stats}
  end

  describe "initial state" do
    test "empty snapshot has idle status with zero counters", %{stats: stats} do
      snapshot = Stats.get_snapshot(stats)

      assert snapshot.status == :idle
      assert snapshot.active_count == 0
      assert snapshot.throughput == 0.0
      assert snapshot.avg_duration_ms == nil
      assert snapshot.error_count == 0
      assert snapshot.last_error == nil
      assert snapshot.queue_depth == 0
      assert snapshot.total_downloaded == 0
      assert snapshot.total_failed == 0
      assert snapshot.recent_errors == []
    end
  end

  describe "empty_snapshot/0" do
    test "returns a valid snapshot without a running GenServer" do
      snapshot = Stats.empty_snapshot()

      assert snapshot.status == :idle
      assert snapshot.active_count == 0
      assert snapshot.queue_depth == 0
      assert snapshot.total_downloaded == 0
      assert snapshot.total_failed == 0
      assert snapshot.recent_errors == []
    end
  end

  describe "active count tracking" do
    test "start increments active count, stop decrements it", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.active_count == 1
      assert snapshot.status == :active

      Stats.download_stop(stats, 100_000, :ok, :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.active_count == 0
    end

    test "multiple concurrent starts track correctly", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-1")
      Stats.download_start(stats, :backdrop, "entity-1")
      Stats.download_start(stats, :logo, "entity-2")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.active_count == 3

      Stats.download_stop(stats, 100_000, :ok, :poster, "entity-1")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.active_count == 2
    end

    test "exception decrements active count", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")
      Stats.download_exception(stats, 50_000, "connection reset", :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.active_count == 0
    end

    test "active count never goes below zero", %{stats: stats} do
      Stats.download_stop(stats, 100_000, :ok, :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.active_count == 0
    end
  end

  describe "throughput window" do
    test "completions within window contribute to throughput", %{stats: stats} do
      for _ <- 1..5 do
        Stats.download_stop(stats, 100_000, :ok, :poster, "entity-123")
      end

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.throughput > 0.0
    end
  end

  describe "error tracking" do
    test "exception increments error count and sets last_error", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")
      Stats.download_exception(stats, 50_000, "TMDB CDN timeout", :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.error_count == 1
      assert snapshot.last_error != nil
      {message, _time} = snapshot.last_error
      assert message == "TMDB CDN timeout"
    end

    test "error result on stop increments total_failed", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")
      Stats.download_stop(stats, 100_000, :error, :poster, "entity-123", "404 not found")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.total_failed == 1
    end

    test "multiple errors accumulate", %{stats: stats} do
      for _ <- 1..3 do
        Stats.download_start(stats, :poster, "entity-123")
        Stats.download_exception(stats, 50_000, "network error", :poster, "entity-123")
      end

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.error_count == 3
    end
  end

  describe "recent_errors ring buffer" do
    test "exceptions are recorded in recent_errors", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")
      Stats.download_exception(stats, 50_000, "TMDB timeout", :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert length(snapshot.recent_errors) == 1
      [error] = snapshot.recent_errors
      assert error.file_path == "entity-123/poster"
      assert error.error_message == "TMDB timeout"
      assert error.stage == :download_resize
      assert %DateTime{} = error.updated_at
    end

    test "error stop results are recorded in recent_errors", %{stats: stats} do
      Stats.download_stop(stats, 100_000, :error, :backdrop, "entity-456", "CDN 503")

      snapshot = Stats.get_snapshot(stats)
      assert length(snapshot.recent_errors) == 1
      [error] = snapshot.recent_errors
      assert error.file_path == "entity-456/backdrop"
      assert error.stage == :download_resize
    end

    test "recent_errors are bounded to 20 entries", %{stats: stats} do
      for i <- 1..25 do
        Stats.download_exception(stats, 50_000, "error #{i}", :poster, "entity-#{i}")
      end

      snapshot = Stats.get_snapshot(stats)
      assert length(snapshot.recent_errors) == 20
      assert snapshot.recent_errors |> hd() |> Map.get(:error_message) == "error 25"
    end

    test "successful stops do not create error entries", %{stats: stats} do
      Stats.download_stop(stats, 100_000, :ok, :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.recent_errors == []
    end
  end

  describe "queue depth" do
    test "queue_depth updates to latest value", %{stats: stats} do
      Stats.queue_depth(stats, 5)

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.queue_depth == 5

      Stats.queue_depth(stats, 2)

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.queue_depth == 2
    end
  end

  describe "lifetime counters" do
    test "total_downloaded increments on successful stop", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")
      Stats.download_stop(stats, 100_000, :ok, :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.total_downloaded == 1
    end

    test "total_failed increments on exception", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")
      Stats.download_exception(stats, 50_000, "connection refused", :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.total_failed == 1
    end

    test "total_failed increments on error stop", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")
      Stats.download_stop(stats, 100_000, :error, :poster, "entity-123", "404 not found")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.total_failed == 1
    end
  end

  describe "status derivation" do
    test "idle when active_count is 0", %{stats: stats} do
      snapshot = Stats.get_snapshot(stats)
      assert snapshot.status == :idle
    end

    test "active when active_count > 0", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.status == :active
    end

    test "saturated when active_count >= 3", %{stats: stats} do
      for i <- 1..3 do
        Stats.download_start(stats, :poster, "entity-#{i}")
      end

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.status == :saturated
    end

    test "erroring when active and recent errors", %{stats: stats} do
      Stats.download_start(stats, :poster, "entity-123")
      Stats.download_exception(stats, 50_000, "fail", :poster, "entity-123")
      Stats.download_start(stats, :backdrop, "entity-123")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.status == :erroring
    end
  end

  describe "average duration" do
    test "calculates average duration from window completions", %{stats: stats} do
      for duration <- [1_000_000, 2_000_000, 3_000_000] do
        Stats.download_stop(stats, duration, :ok, :poster, "entity-123")
      end

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.avg_duration_ms > 0
    end

    test "returns nil when no completions in window", %{stats: stats} do
      snapshot = Stats.get_snapshot(stats)
      assert snapshot.avg_duration_ms == nil
    end
  end
end
