defmodule MediaCentarr.WatchHistoryTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.TestFactory
  alias MediaCentarr.WatchHistory

  defp count_rows_fetched(fun) do
    ref = make_ref()
    parent = self()
    handler_id = {:watch_history_rows_fetched, ref}

    :ok =
      :telemetry.attach(
        handler_id,
        [:media_centarr, :repo, :query],
        fn _, _, metadata, _ ->
          case metadata[:result] do
            {:ok, %{num_rows: n}} -> send(parent, {:rows, ref, n})
            _ -> :ok
          end
        end,
        nil
      )

    try do
      fun.()
      drain_rows(ref, 0)
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_rows(ref, total) do
    receive do
      {:rows, ^ref, n} -> drain_rows(ref, total + n)
    after
      0 -> total
    end
  end

  describe "stats/0" do
    test "returns zero-shape when no events exist" do
      assert WatchHistory.stats() == %{
               total_count: 0,
               total_seconds: 0.0,
               streak: 0,
               heatmap: %{}
             }
    end

    test "computes count, seconds, and heatmap entries" do
      today = Date.utc_today()
      now = DateTime.new!(today, ~T[12:00:00], "Etc/UTC")
      yesterday = Date.add(today, -1)
      yest_dt = DateTime.new!(yesterday, ~T[12:00:00], "Etc/UTC")

      TestFactory.create_watch_event(%{title: "A", duration_seconds: 100.0, completed_at: now})
      TestFactory.create_watch_event(%{title: "B", duration_seconds: 200.0, completed_at: now})
      TestFactory.create_watch_event(%{title: "C", duration_seconds: 50.0, completed_at: yest_dt})

      stats = WatchHistory.stats()

      assert stats.total_count == 3
      assert stats.total_seconds == 350.0
      assert stats.streak == 2
      assert stats.heatmap[today] == 2
      assert stats.heatmap[yesterday] == 1
    end

    test "rows fetched does not grow with event count (uses DB aggregates)" do
      today = Date.utc_today()
      now = DateTime.new!(today, ~T[12:00:00], "Etc/UTC")

      for _ <- 1..5,
          do: TestFactory.create_watch_event(%{title: "A", completed_at: now})

      baseline = count_rows_fetched(fn -> WatchHistory.stats() end)

      for _ <- 1..45,
          do: TestFactory.create_watch_event(%{title: "B", completed_at: now})

      expanded = count_rows_fetched(fn -> WatchHistory.stats() end)

      assert expanded == baseline,
             "stats/0 rows fetched should not grow with event count. " <>
               "Baseline (5 events) = #{baseline}, expanded (50 events) = #{expanded}"
    end
  end

  describe "heatmap_cells_by_type/0" do
    test "returns 364 cells for each of nil, :movie, :episode, :video_object" do
      result = WatchHistory.heatmap_cells_by_type()

      for type <- [nil, :movie, :episode, :video_object] do
        assert is_list(result[type]), "missing key #{inspect(type)}"
        assert length(result[type]) == 364
      end
    end

    test "partitions counts by entity_type correctly" do
      today = Date.utc_today()
      now = DateTime.new!(today, ~T[12:00:00], "Etc/UTC")

      TestFactory.create_watch_event(%{entity_type: :movie, completed_at: now})
      TestFactory.create_watch_event(%{entity_type: :movie, completed_at: now})
      TestFactory.create_watch_event(%{entity_type: :episode, completed_at: now})

      result = WatchHistory.heatmap_cells_by_type()

      today_cell_movie = Enum.find(result[:movie], &(&1.date == today))
      today_cell_episode = Enum.find(result[:episode], &(&1.date == today))
      today_cell_video = Enum.find(result[:video_object], &(&1.date == today))
      today_cell_all = Enum.find(result[nil], &(&1.date == today))

      assert today_cell_movie.count == 2
      assert today_cell_episode.count == 1
      assert today_cell_video.count == 0
      assert today_cell_all.count == 3
    end

    test "rows fetched does not grow with event count (uses DB aggregates)" do
      today = Date.utc_today()
      now = DateTime.new!(today, ~T[12:00:00], "Etc/UTC")

      for _ <- 1..5,
          do: TestFactory.create_watch_event(%{title: "A", completed_at: now})

      baseline = count_rows_fetched(fn -> WatchHistory.heatmap_cells_by_type() end)

      for _ <- 1..45,
          do: TestFactory.create_watch_event(%{title: "B", completed_at: now})

      expanded = count_rows_fetched(fn -> WatchHistory.heatmap_cells_by_type() end)

      assert expanded == baseline,
             "heatmap_cells_by_type/0 rows fetched should not grow with event count. " <>
               "Baseline (5 events) = #{baseline}, expanded (50 events) = #{expanded}"
    end
  end

  describe "rewatch_count/2" do
    test "returns count for an entity with events" do
      movie = TestFactory.create_movie(%{name: "Sample Movie"})
      for _ <- 1..3, do: TestFactory.create_watch_event(%{movie_id: movie.id, entity_type: :movie})

      assert WatchHistory.rewatch_count(:movie, movie.id) == 3
    end

    test "returns 0 for an entity with no events" do
      movie = TestFactory.create_movie(%{name: "Dark City"})
      assert WatchHistory.rewatch_count(:movie, movie.id) == 0
    end
  end

  describe "top_rewatches/1" do
    test "delegates to Rewatch.top_rewatches/1" do
      movie = TestFactory.create_movie(%{name: "Solaris"})
      for _ <- 1..2, do: TestFactory.create_watch_event(%{movie_id: movie.id, entity_type: :movie})

      [row] = WatchHistory.top_rewatches(min: 2, limit: 5)

      assert row.entity_id == movie.id
      assert row.count == 2
    end
  end

  describe "rewatch_count_map/1" do
    test "returns a map of entity_id => count for the given type" do
      movie_a = TestFactory.create_movie(%{name: "Stalker"})
      movie_b = TestFactory.create_movie(%{name: "Tarkovsky Collection"})
      TestFactory.create_watch_event(%{movie_id: movie_a.id, entity_type: :movie})
      for _ <- 1..2, do: TestFactory.create_watch_event(%{movie_id: movie_b.id, entity_type: :movie})

      counts = WatchHistory.rewatch_count_map(:movie)

      assert counts[movie_a.id] == 1
      assert counts[movie_b.id] == 2
    end
  end
end
