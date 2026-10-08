defmodule MediaCentaur.WatchHistoryTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory, only: [create_profile: 1, create_watch_event: 1, owner_profile_id: 0]

  alias MediaCentaur.TestFactory
  alias MediaCentaur.WatchHistory

  defp count_rows_fetched(fun) do
    ref = make_ref()
    parent = self()
    handler_id = {:watch_history_rows_fetched, ref}

    :ok =
      :telemetry.attach(
        handler_id,
        [:media_centaur, :repo, :query],
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

  describe "stats/1" do
    test "returns zero-shape when no events exist" do
      assert WatchHistory.stats(owner_profile_id()) == %{
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

      stats = WatchHistory.stats(owner_profile_id())

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

      baseline = count_rows_fetched(fn -> WatchHistory.stats(owner_profile_id()) end)

      for _ <- 1..45,
          do: TestFactory.create_watch_event(%{title: "B", completed_at: now})

      expanded = count_rows_fetched(fn -> WatchHistory.stats(owner_profile_id()) end)

      assert expanded == baseline,
             "stats/1 rows fetched should not grow with event count. " <>
               "Baseline (5 events) = #{baseline}, expanded (50 events) = #{expanded}"
    end
  end

  describe "heatmap_cells_by_type/1" do
    test "returns 364 cells for each of nil, :movie, :episode, :video_object" do
      result = WatchHistory.heatmap_cells_by_type(owner_profile_id())

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

      result = WatchHistory.heatmap_cells_by_type(owner_profile_id())

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

      baseline = count_rows_fetched(fn -> WatchHistory.heatmap_cells_by_type(owner_profile_id()) end)

      for _ <- 1..45,
          do: TestFactory.create_watch_event(%{title: "B", completed_at: now})

      expanded = count_rows_fetched(fn -> WatchHistory.heatmap_cells_by_type(owner_profile_id()) end)

      assert expanded == baseline,
             "heatmap_cells_by_type/1 rows fetched should not grow with event count. " <>
               "Baseline (5 events) = #{baseline}, expanded (50 events) = #{expanded}"
    end
  end

  describe "rewatch_count_map/2" do
    test "returns a map of entity_id => count for the given type" do
      movie_a = TestFactory.create_movie(%{name: "Movie A"})
      movie_b = TestFactory.create_movie(%{name: "Movie B"})
      TestFactory.create_watch_event(%{movie_id: movie_a.id, entity_type: :movie})
      for _ <- 1..2, do: TestFactory.create_watch_event(%{movie_id: movie_b.id, entity_type: :movie})

      counts = WatchHistory.rewatch_count_map(owner_profile_id(), :movie)

      assert counts[movie_a.id] == 1
      assert counts[movie_b.id] == 2
    end
  end

  describe "scope" do
    setup do
      movie = TestFactory.create_movie(%{name: "Sample Movie"})
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id

      create_watch_event(%{
        profile_id: me,
        movie_id: movie.id,
        title: "Sample Movie",
        duration_seconds: 3600.0
      })

      create_watch_event(%{
        profile_id: ana,
        movie_id: movie.id,
        title: "Sample Movie",
        duration_seconds: 1800.0
      })

      create_watch_event(%{
        profile_id: ana,
        movie_id: movie.id,
        title: "Sample Movie",
        duration_seconds: 1800.0
      })

      %{movie: movie, me: me, ana: ana}
    end

    test "a profile reads its own events and aggregates", %{movie: movie, me: me, ana: ana} do
      assert [%{duration_seconds: 3600.0}] = WatchHistory.list_events(me)
      assert length(WatchHistory.list_events(ana)) == 2
      assert WatchHistory.stats(me).total_count == 1
      assert WatchHistory.stats(ana).total_seconds == 3600.0
      assert WatchHistory.rewatch_count_map(me, :movie) == %{movie.id => 1}
      assert WatchHistory.rewatch_count_map(ana, :movie) == %{movie.id => 2}
      assert length(WatchHistory.recent_events(me, 5)) == 1
      assert Enum.sort(WatchHistory.profile_ids_with_events()) == Enum.sort([me, ana])
    end

    test ":all is the install-wide view", %{movie: movie} do
      assert WatchHistory.stats(:all).total_count == 3
      assert WatchHistory.stats(:all).total_seconds == 7200.0
      assert WatchHistory.rewatch_count_map(:all, :movie) == %{movie.id => 3}
      assert length(WatchHistory.recent_events(:all, 5)) == 3
    end

    test "removing a profile removes its events", %{me: me, ana: ana} do
      :ok = MediaCentaur.Profiles.remove(MediaCentaur.Profiles.get(ana))
      assert WatchHistory.list_events(ana) == []
      assert WatchHistory.stats(:all).total_count == 1
      assert WatchHistory.profile_ids_with_events() == [me]
    end
  end
end
