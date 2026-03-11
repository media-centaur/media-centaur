defmodule MediaCentaur.Pipeline.StatsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Pipeline.Stats

  @stages [:parse, :search, :fetch_metadata, :ingest]

  setup do
    name = :"stats_#{System.unique_integer([:positive])}"
    stats = start_supervised!({Stats, name: name})
    {:ok, stats: stats}
  end

  describe "initial state" do
    test "empty snapshot has all stages idle with zero counters", %{stats: stats} do
      snapshot = Stats.get_snapshot(stats)

      for stage <- @stages do
        stage_data = snapshot.stages[stage]
        assert stage_data.active_count == 0
        assert stage_data.status == :idle
        assert stage_data.throughput == 0.0
        assert stage_data.error_count == 0
        assert stage_data.last_error == nil
      end

      assert snapshot.queue_depth == 0
      assert snapshot.total_processed == 0
      assert snapshot.total_failed == 0
      assert snapshot.needs_review_count == 0
      assert snapshot.recent_errors == []
    end
  end

  describe "empty_snapshot/0" do
    test "returns a valid snapshot without a running GenServer" do
      snapshot = Stats.empty_snapshot()

      for stage <- @stages do
        assert snapshot.stages[stage].active_count == 0
        assert snapshot.stages[stage].status == :idle
      end

      assert snapshot.queue_depth == 0
      assert snapshot.recent_errors == []
    end
  end

  describe "active count tracking" do
    test "start increments active count, stop decrements it", %{stats: stats} do
      Stats.stage_start(stats, :parse, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.active_count == 1
      assert snapshot.stages.parse.status == :active

      Stats.stage_stop(stats, :parse, 100_000, :ok, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.active_count == 0
    end

    test "multiple concurrent starts track correctly", %{stats: stats} do
      Stats.stage_start(stats, :search, "a.mkv")
      Stats.stage_start(stats, :search, "b.mkv")
      Stats.stage_start(stats, :search, "c.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.search.active_count == 3

      Stats.stage_stop(stats, :search, 100_000, :ok, "a.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.search.active_count == 2
    end

    test "exception decrements active count", %{stats: stats} do
      Stats.stage_start(stats, :ingest, "test.mkv")
      Stats.stage_exception(stats, :ingest, 50_000, "something failed", "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.ingest.active_count == 0
    end

    test "active count never goes below zero", %{stats: stats} do
      Stats.stage_stop(stats, :parse, 100_000, :ok, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.active_count == 0
    end
  end

  describe "throughput window" do
    test "completions within window contribute to throughput", %{stats: stats} do
      for _ <- 1..5 do
        Stats.stage_stop(stats, :parse, 100_000, :ok, "test.mkv")
      end

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.throughput > 0.0
    end

    test "old completions are pruned from window", %{stats: stats} do
      old_time = System.monotonic_time(:millisecond) - 10_000

      Stats.stage_stop_at(stats, :parse, 100_000, :ok, old_time, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.throughput == 0.0
    end
  end

  describe "error tracking" do
    test "exception increments error count and sets last_error", %{stats: stats} do
      Stats.stage_start(stats, :search, "test.mkv")
      Stats.stage_exception(stats, :search, 50_000, "TMDB timeout", "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.search.error_count == 1
      assert snapshot.stages.search.last_error != nil
      {message, _time} = snapshot.stages.search.last_error
      assert message == "TMDB timeout"
    end

    test "error result on stop increments total_failed", %{stats: stats} do
      Stats.stage_start(stats, :search, "test.mkv")
      Stats.stage_stop(stats, :search, 100_000, :error, "test.mkv", {:http_error, 401})

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.total_failed == 1
    end

    test "multiple errors accumulate", %{stats: stats} do
      for _ <- 1..3 do
        Stats.stage_start(stats, :fetch_metadata, "test.mkv")
        Stats.stage_exception(stats, :fetch_metadata, 50_000, "network error", "test.mkv")
      end

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.fetch_metadata.error_count == 3
    end
  end

  describe "recent_errors ring buffer" do
    test "exceptions are recorded in recent_errors", %{stats: stats} do
      Stats.stage_start(stats, :search, "/media/movie.mkv")
      Stats.stage_exception(stats, :search, 50_000, "TMDB timeout", "/media/movie.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert length(snapshot.recent_errors) == 1
      [error] = snapshot.recent_errors
      assert error.file_path == "/media/movie.mkv"
      assert error.error_message == "TMDB timeout"
      assert error.stage == :search
      assert %DateTime{} = error.updated_at
    end

    test "error stop results are recorded in recent_errors", %{stats: stats} do
      Stats.stage_stop(stats, :search, 100_000, :error, "/media/movie.mkv", {:http_error, 401})

      snapshot = Stats.get_snapshot(stats)
      assert length(snapshot.recent_errors) == 1
      [error] = snapshot.recent_errors
      assert error.file_path == "/media/movie.mkv"
      assert error.stage == :search
    end

    test "recent_errors are bounded to 50 entries", %{stats: stats} do
      for i <- 1..60 do
        Stats.stage_exception(stats, :parse, 50_000, "error #{i}", "/media/file#{i}.mkv")
      end

      snapshot = Stats.get_snapshot(stats)
      assert length(snapshot.recent_errors) == 50
      # Most recent error should be first
      assert snapshot.recent_errors |> hd() |> Map.get(:error_message) == "error 60"
    end

    test "successful stops do not create error entries", %{stats: stats} do
      Stats.stage_stop(stats, :parse, 100_000, :ok, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.recent_errors == []
    end
  end

  describe "needs_review counter" do
    test "needs_review increments counter", %{stats: stats} do
      Stats.needs_review(stats, "test.mkv")
      Stats.needs_review(stats, "test2.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.needs_review_count == 2
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
    test "total_processed increments on successful stop", %{stats: stats} do
      Stats.stage_start(stats, :ingest, "test.mkv")
      Stats.stage_stop(stats, :ingest, 100_000, :ok, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.total_processed == 1
    end

    test "total_processed does not increment for non-terminal stages", %{stats: stats} do
      Stats.stage_start(stats, :parse, "test.mkv")
      Stats.stage_stop(stats, :parse, 100_000, :ok, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.total_processed == 0
    end

    test "needs_review stop on search counts as total_processed", %{stats: stats} do
      Stats.stage_start(stats, :search, "test.mkv")
      Stats.stage_stop(stats, :search, 100_000, :needs_review, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.total_processed == 0
      assert snapshot.total_failed == 0
    end
  end

  describe "status derivation" do
    test "idle when active_count is 0", %{stats: stats} do
      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.status == :idle
    end

    test "active when active_count > 0", %{stats: stats} do
      Stats.stage_start(stats, :parse, "test.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.status == :active
    end

    test "saturated when active_count >= 10", %{stats: stats} do
      for i <- 1..10 do
        Stats.stage_start(stats, :fetch_metadata, "test#{i}.mkv")
      end

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.fetch_metadata.status == :saturated
    end

    test "erroring when active and recent errors", %{stats: stats} do
      Stats.stage_start(stats, :search, "test.mkv")
      Stats.stage_exception(stats, :search, 50_000, "fail", "test.mkv")
      Stats.stage_start(stats, :search, "test2.mkv")

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.search.status == :erroring
    end
  end

  describe "average duration" do
    test "calculates average duration from window completions", %{stats: stats} do
      for duration <- [1_000_000, 2_000_000, 3_000_000] do
        Stats.stage_stop(stats, :parse, duration, :ok, "test.mkv")
      end

      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.avg_duration_ms > 0
    end

    test "returns nil when no completions in window", %{stats: stats} do
      snapshot = Stats.get_snapshot(stats)
      assert snapshot.stages.parse.avg_duration_ms == nil
    end
  end
end
