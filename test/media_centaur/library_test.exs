defmodule MediaCentaur.LibraryTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory
  alias MediaCentaur.Library

  # Records the file as present in watcher_files so Browser queries include it.

  defp count_queries(fun) do
    ref = make_ref()
    parent = self()
    handler_id = {:library_query_count, ref}

    # Ecto emits `[:repo, :query]` telemetry synchronously in the process that
    # ran the query, so `self()` inside the handler is that process. Counting
    # only queries emitted by `parent` (the test process running `fun`) scopes
    # the measurement to the function under test — without this filter, queries
    # from background workers (projection Cache.Workers refreshing on the
    # entity-creation PubSub, etc.) firing during the window get counted too,
    # which made these counts flake under full-suite parallelism.
    :ok =
      :telemetry.attach(
        handler_id,
        [:media_centaur, :repo, :query],
        fn _, _, _, _ -> if self() == parent, do: send(parent, {:query, ref}) end,
        nil
      )

    try do
      fun.()
      drain_queries(ref, 0)
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(ref, count) do
    receive do
      {:query, ^ref} -> drain_queries(ref, count + 1)
    after
      0 -> count
    end
  end

  # Post-Phase-7 no-op (legacy hook from the library-presence-unification campaign).
  defp record_present(_file), do: :ok

  describe "find_or_create_movie_for_series/1" do
    test "writes tmdb and imdb ExternalId rows for a new child movie" do
      series = create_movie_series(%{name: "Sample Collection"})

      {:ok, movie} =
        Library.Containers.find_or_create_movie_for_series(%{
          movie_series_id: series.id,
          tmdb_id: "155",
          imdb_id: "tt0000155",
          name: "Sample Movie Two",
          position: 1
        })

      external_ids =
        movie
        |> Repo.preload(:external_ids)
        |> Map.fetch!(:external_ids)
        |> Enum.map(&{&1.source, &1.external_id})
        |> Enum.sort()

      assert external_ids == [{"imdb", "tt0000155"}, {"tmdb", "155"}]
    end
  end

  describe "load_modal_entry/1 collection hoist" do
    test "a sole-possessed collection movie loads as a faithful movie, not the collection" do
      ms = create_movie_series(%{name: "Singleton Collection", genres: ["Adventure"]})

      child =
        create_movie(%{
          movie_series_id: ms.id,
          name: "Only Child",
          genres: ["Action"],
          position: 0
        })

      record_present(create_linked_file(%{movie_id: child.id}))

      assert {:ok, %{entity: entity}} = Library.ModalEntry.load(child.id)
      assert entity.type == :movie
      assert entity.id == child.id
      assert entity.name == "Only Child"
      assert entity.genres == ["Action"]
      assert entity.collection == %{id: ms.id, name: "Singleton Collection"}
    end

    test "opening a hoisted collection by its series id resolves to the sole movie" do
      ms = create_movie_series(%{name: "Singleton Collection"})
      child = create_movie(%{movie_series_id: ms.id, name: "Only Child", position: 0})
      record_present(create_linked_file(%{movie_id: child.id}))

      assert {:ok, %{entity: entity}} = Library.ModalEntry.load(ms.id)
      assert entity.type == :movie
      assert entity.id == child.id
    end

    test "a multi-possessed collection loads as the collection" do
      ms = create_movie_series(%{name: "Trilogy"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Part 2", position: 1})
      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      assert {:ok, %{entity: entity}} = Library.ModalEntry.load(ms.id)
      assert entity.type == :movie_series
      assert entity.id == ms.id
    end
  end

  describe "list_in_progress/1" do
    test "returns empty list when no entities exist" do
      assert Library.list_in_progress() == []
    end

    test "returns empty list when no in-progress watch progress exists" do
      movie = create_standalone_movie(%{name: "Completed Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 100.0,
        duration_seconds: 100.0,
        completed: true
      })

      assert Library.list_in_progress() == []
    end

    test "returns in-progress movie with required shape" do
      movie = create_standalone_movie(%{name: "Prior Lives"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})

      results = Library.list_in_progress()

      assert length(results) == 1
      row = hd(results)
      assert row.entity_id == movie.id
      assert row.entity_name == "Prior Lives"
      assert is_integer(row.progress_pct)
      assert row.progress_pct >= 0 and row.progress_pct <= 100
      assert Map.has_key?(row, :backdrop_url)
    end

    test "movie progress_pct reflects in-episode position, not just completion" do
      # Continue Watching's progress bar must show how far through the
      # movie the user actually is. The previous `episodes_completed /
      # episodes_total` formula yielded 0 % for any in-progress movie
      # (movies are 1 episode and never completed mid-watch), so the bar
      # was always empty until the moment they finished — at which point
      # the row disappeared from Continue Watching anyway. Useless.
      movie = create_standalone_movie(%{name: "Halfway Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      create_watch_progress(%{movie_id: movie.id, position_seconds: 50.0, duration_seconds: 100.0})

      [row] = Library.list_in_progress()
      assert row.progress_pct == 50
    end

    test "tv_series progress_pct weights current-episode position into the overall fraction" do
      # 5 of 10 episodes completed plus halfway through the 6th = 55 %
      # overall. The simpler "completion only" model would have shown 50 %.
      #
      # Per Library Schema v2 Phase 2 Task B the file-presence row is
      # attached at the Episode level via PlayableItem — set the first
      # episode up as the present-file holder.
      series = create_tv_series(%{name: "Weighted Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})

      episodes =
        for ep <- 1..10 do
          create_episode(%{
            season_id: season.id,
            episode_number: ep,
            name: "S1E#{ep}",
            content_url: "/tv/weighted/s01e#{ep}.mkv"
          })
        end

      first_episode = hd(episodes)
      playable_item = create_playable_item_for_episode(first_episode)

      record_present(
        create_linked_file(%{
          playable_item_id: playable_item.id,
          file_path: first_episode.content_url
        })
      )

      # First five episodes completed.
      for ep <- Enum.take(episodes, 5) do
        create_watch_progress(%{
          episode_id: ep.id,
          position_seconds: 1000.0,
          duration_seconds: 1000.0,
          completed: true
        })
      end

      # Sixth episode in progress at 50 %.
      sixth = Enum.at(episodes, 5)

      create_watch_progress(%{
        episode_id: sixth.id,
        position_seconds: 500.0,
        duration_seconds: 1000.0
      })

      [row] = Library.list_in_progress()
      assert row.progress_pct == 55
    end

    test "tv_series progress_pct counts only present episodes in the denominator" do
      series = create_tv_series(%{name: "Partial Files Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})

      [first_episode, _second_episode] =
        for episode_number <- 1..2 do
          create_episode(%{
            season_id: season.id,
            episode_number: episode_number,
            name: "S1E#{episode_number}",
            content_url: "/tv/partial/s01e#{episode_number}.mkv"
          })
        end

      # A third episode record with no file — not watchable, so it must
      # not dilute the bar.
      _fileless =
        create_episode(%{season_id: season.id, episode_number: 3, name: "S1E3"})

      create_watch_progress(%{
        episode_id: first_episode.id,
        position_seconds: 1000.0,
        duration_seconds: 1000.0,
        completed: true
      })

      [row] = Library.list_in_progress()
      assert row.progress_pct == 50
    end

    # UIDR-025: collections are filing, not content. The unit of
    # "continuing" is the member movie — its own identity, its own
    # within-movie bar. The collection entity never appears on this
    # surface and has no completion fraction.
    test "a paused member of a multi-child collection appears as that movie" do
      ms = create_movie_series(%{name: "Sample Trilogy"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Part 2", position: 1})
      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      create_watch_progress(%{
        movie_id: part1.id,
        position_seconds: 100.0,
        duration_seconds: 100.0,
        completed: true
      })

      create_watch_progress(%{
        movie_id: part2.id,
        position_seconds: 40.0,
        duration_seconds: 100.0
      })

      [row] = Library.list_in_progress()
      assert row.entity_id == part2.id
      assert row.entity_name == "Part 2"
      assert row.progress_pct == 40
    end

    test "a finished member with the next member unstarted yields no row" do
      ms = create_movie_series(%{name: "Sample Duology"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Part 2", position: 1})
      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      create_watch_progress(%{
        movie_id: part1.id,
        position_seconds: 100.0,
        duration_seconds: 100.0,
        completed: true
      })

      assert Library.list_in_progress() == []
    end

    test "two paused members yield two independent rows" do
      ms = create_movie_series(%{name: "Sample Trilogy"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Part 1", position: 0})
      part3 = create_movie(%{movie_series_id: ms.id, name: "Part 3", position: 2})
      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part3.id}))

      create_watch_progress(%{movie_id: part1.id, position_seconds: 20.0, duration_seconds: 100.0})
      create_watch_progress(%{movie_id: part3.id, position_seconds: 60.0, duration_seconds: 100.0})

      rows = Library.list_in_progress()
      assert Enum.sort(Enum.map(rows, & &1.entity_id)) == Enum.sort([part1.id, part3.id])
      refute Enum.any?(rows, &(&1.entity_id == ms.id))
    end

    test "a member movie without art falls back to collection art (UIDR-021 ladder)" do
      ms = create_movie_series(%{name: "Sample Trilogy"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Part 2", position: 1})
      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      create_image(%{
        movie_series_id: ms.id,
        role: "backdrop",
        content_url: "#{ms.id}/backdrop.jpg",
        extension: "jpg"
      })

      create_watch_progress(%{movie_id: part2.id, position_seconds: 40.0, duration_seconds: 100.0})

      [row] = Library.list_in_progress()
      assert row.entity_id == part2.id
      assert row.backdrop_url =~ "backdrop.jpg"
    end

    test "does not return completed progress" do
      movie = create_standalone_movie(%{name: "Watched Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 100.0,
        duration_seconds: 100.0,
        completed: true
      })

      assert Library.list_in_progress() == []
    end

    test "respects the limit option" do
      Enum.each(1..5, fn index ->
        movie = create_standalone_movie(%{name: "Movie #{index}"})
        record_present(create_linked_file(%{movie_id: movie.id}))
        create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})
      end)

      results = Library.list_in_progress(limit: 3)
      assert length(results) == 3
    end

    test "issues at most 15 queries regardless of library size" do
      for index <- 1..20 do
        movie = create_standalone_movie(%{name: "Movie #{index}"})
        record_present(create_linked_file(%{movie_id: movie.id}))
        create_watch_progress(%{movie_id: movie.id, position_seconds: 30.0, duration_seconds: 100.0})
      end

      for index <- 1..5 do
        series = create_tv_series(%{name: "Series #{index}"})
        record_present(create_linked_file(%{tv_series_id: series.id}))
        season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})
        episode = create_episode(%{season_id: season.id, episode_number: 1, name: "S1E1"})
        create_watch_progress(%{episode_id: episode.id, position_seconds: 10.0, duration_seconds: 60.0})
      end

      query_count = count_queries(fn -> Library.list_in_progress(limit: 12) end)
      assert query_count <= 15, "Expected at most 15 queries, got #{query_count}"
    end

    test "query count does not grow with the number of in-progress TV series (no N+1)" do
      # Baseline: 1 TV series with one in-progress episode.
      seed_in_progress_tv_series(1, 1)
      baseline = count_queries(fn -> Library.list_in_progress(limit: 12) end)

      # Add 9 more (10 total). Per-series WatchProgress fan-out would inflate
      # the count by ~9 queries; with a single batched WatchProgress query the
      # count must stay constant.
      seed_in_progress_tv_series(9, 1, name_prefix: "Extra")
      expanded = count_queries(fn -> Library.list_in_progress(limit: 12) end)

      assert expanded == baseline,
             "Query count should not grow with TV series count (N+1 detected). " <>
               "Baseline (1 series) = #{baseline}, expanded (10 series) = #{expanded}"
    end

    test "finished series do not consume the limit and starve unfinished ones" do
      # The SQL `limit` used to be applied before the completed-series test,
      # which ran in Elixir afterwards. Six finished series ordered ahead of
      # the unfinished one would fill the fetcher's window and then all be
      # rejected, so Continue Watching rendered short — the row's whole job
      # is to surface the thing you haven't finished.
      now = DateTime.utc_now()

      # Six series with exactly one episode each, all of it watched — the
      # file is linked through the episode's own PlayableItem so no synthetic
      # unwatched episode is created alongside it.
      for index <- 1..6 do
        series = create_tv_series(%{name: "Finished #{index}"})
        season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})
        episode = create_episode(%{season_id: season.id, episode_number: 1, name: "S1E1"})
        playable_item = create_playable_item_for_episode(episode)
        record_present(create_linked_file(%{playable_item_id: playable_item.id}))

        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 60.0,
          duration_seconds: 60.0,
          completed: true,
          last_watched_at: DateTime.add(now, -index, :minute)
        })
      end

      # One series watched less recently than all six, with an episode left.
      unfinished = create_tv_series(%{name: "Still Going"})
      season = create_season(%{tv_series_id: unfinished.id, season_number: 1, name: "S1"})
      watched = create_episode(%{season_id: season.id, episode_number: 1, name: "S1E1"})
      unwatched = create_episode(%{season_id: season.id, episode_number: 2, name: "S1E2"})
      watched_item = create_playable_item_for_episode(watched)
      unwatched_item = create_playable_item_for_episode(unwatched)
      record_present(create_linked_file(%{playable_item_id: watched_item.id}))
      record_present(create_linked_file(%{playable_item_id: unwatched_item.id}))

      create_watch_progress(%{
        episode_id: watched.id,
        position_seconds: 60.0,
        duration_seconds: 60.0,
        completed: true,
        last_watched_at: DateTime.add(now, -10, :minute)
      })

      names = Enum.map(Library.list_in_progress(limit: 3), & &1.entity_name)

      assert "Still Going" in names
    end
  end

  defp seed_in_progress_tv_series(count, episodes_per_series, opts \\ []) do
    name_prefix = Keyword.get(opts, :name_prefix, "Series")

    for index <- 1..count do
      series = create_tv_series(%{name: "#{name_prefix} #{index}-#{System.unique_integer([:positive])}"})
      record_present(create_linked_file(%{tv_series_id: series.id}))
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})

      for episode_number <- 1..episodes_per_series do
        episode =
          create_episode(%{
            season_id: season.id,
            episode_number: episode_number,
            name: "S1E#{episode_number}",
            content_url: "/tv/#{name_prefix}-#{index}/s01e#{episode_number}.mkv"
          })

        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 10.0,
          duration_seconds: 60.0
        })
      end
    end
  end

  describe "list_in_progress/1 keeps the most recently watched within the limit" do
    # The final row order is decided in Elixir, so a test that only checks
    # sortedness passes even with the SQL `order_by` deleted. What the
    # order_by actually decides is *which* rows survive each per-type
    # `limit` — so each test here seeds more in-progress titles of one
    # container shape than the limit allows and asserts the survivors are
    # the most recently watched. One test per shape, because each shape
    # orders through its own query.

    test "movies" do
      movies =
        for index <- 1..4 do
          movie = create_standalone_movie(%{name: "Movie #{index}"})

          progress =
            create_watch_progress(%{
              movie_id: movie.id,
              position_seconds: 30.0,
              duration_seconds: 100.0
            })

          backdate(progress, :last_watched_at, hours_ago(index))
          {index, movie.id}
        end

      assert surviving_ids(limit: 2) == recent_ids(movies, 2)
    end

    test "video objects" do
      videos =
        for index <- 1..4 do
          video = create_video_object(%{name: "Clip #{index}", content_url: "/media/clip#{index}.mkv"})

          progress =
            create_watch_progress(%{
              video_object_id: video.id,
              position_seconds: 30.0,
              duration_seconds: 100.0
            })

          backdate(progress, :last_watched_at, hours_ago(index))
          {index, video.id}
        end

      assert surviving_ids(limit: 2) == recent_ids(videos, 2)
    end

    test "tv series" do
      series =
        for index <- 1..4 do
          series = create_tv_series(%{name: "Series #{index}"})
          season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})

          # Two present episodes, one watched and one not, so the series
          # counts as started-but-unfinished.
          watched =
            create_episode(%{
              season_id: season.id,
              episode_number: 1,
              name: "S1E1",
              content_url: "/tv/series-#{index}/s01e01.mkv"
            })

          create_episode(%{
            season_id: season.id,
            episode_number: 2,
            name: "S1E2",
            content_url: "/tv/series-#{index}/s01e02.mkv"
          })

          progress =
            create_watch_progress(%{
              episode_id: watched.id,
              position_seconds: 30.0,
              duration_seconds: 100.0
            })

          backdate(progress, :last_watched_at, hours_ago(index))
          {index, series.id}
        end

      assert surviving_ids(limit: 2) == recent_ids(series, 2)
    end

    test "collection member movies" do
      # UIDR-025: the surviving rows are the paused member movies
      # themselves, never their collection containers.
      members =
        for index <- 1..4 do
          collection = create_movie_series(%{name: "Collection #{index}"})

          watched =
            create_movie(%{movie_series_id: collection.id, name: "Part 1 of #{index}", position: 0})

          unwatched =
            create_movie(%{movie_series_id: collection.id, name: "Part 2 of #{index}", position: 1})

          record_present(create_linked_file(%{movie_id: watched.id}))
          record_present(create_linked_file(%{movie_id: unwatched.id}))

          progress =
            create_watch_progress(%{
              movie_id: watched.id,
              position_seconds: 30.0,
              duration_seconds: 100.0
            })

          backdate(progress, :last_watched_at, hours_ago(index))
          {index, watched.id}
        end

      assert surviving_ids(limit: 2) == recent_ids(members, 2)
    end
  end

  # Seeded index 1 is the most recent, so the `count` most recently watched
  # are the lowest indexes.
  defp recent_ids(seeded, count) do
    seeded
    |> Enum.sort_by(fn {index, _id} -> index end)
    |> Enum.take(count)
    |> Enum.map(fn {_index, id} -> id end)
    |> Enum.sort()
  end

  defp surviving_ids(opts) do
    opts |> Library.list_in_progress() |> Enum.map(& &1.entity_id) |> Enum.sort()
  end

  defp hours_ago(hours) do
    DateTime.add(DateTime.utc_now(:second), -hours * 3600, :second)
  end

  describe "list_recently_added/1" do
    test "returns empty list when no entities exist" do
      assert Library.list_recently_added() == []
    end

    test "returns recently added movies with required shape" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      results = Library.list_recently_added()

      assert length(results) == 1
      row = hd(results)
      assert row.id == movie.id
      assert row.name == "Sample Movie"
      assert Map.has_key?(row, :year)
      assert Map.has_key?(row, :poster_url)
    end

    test "returns multiple entity types" do
      movie = create_standalone_movie(%{name: "Movie A"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      series = create_tv_series(%{name: "Series B"})
      record_present(create_linked_file(%{tv_series_id: series.id}))
      results = Library.list_recently_added()
      names = Enum.map(results, & &1.name)

      assert "Movie A" in names
      assert "Series B" in names
    end

    test "includes a present video object" do
      video =
        create_video_object(%{name: "Sample Home Video", content_url: "/media/sample-home-video.mkv"})

      results = Library.list_recently_added()
      row = Enum.find(results, &(&1.id == video.id))

      assert row, "expected the present video object to appear in recently added"
      assert row.name == "Sample Home Video"
      assert Map.has_key?(row, :poster_url)
    end

    test "respects the limit option" do
      Enum.each(1..10, fn index ->
        movie = create_standalone_movie(%{name: "Movie #{index}"})
        record_present(create_linked_file(%{movie_id: movie.id}))
      end)

      results = Library.list_recently_added(limit: 5)
      assert length(results) == 5
    end

    test "issues at most 8 queries regardless of library size" do
      for index <- 1..30 do
        movie = create_standalone_movie(%{name: "Movie #{index}"})
        record_present(create_linked_file(%{movie_id: movie.id}))
      end

      for index <- 1..10 do
        series = create_tv_series(%{name: "Series #{index}"})
        record_present(create_linked_file(%{tv_series_id: series.id}))
      end

      query_count = count_queries(fn -> Library.list_recently_added(limit: 16) end)
      assert query_count <= 8, "Expected at most 8 queries, got #{query_count}"
    end
  end

  describe "list_hero_candidates/1" do
    test "returns empty list when no entities exist" do
      assert Library.list_hero_candidates() == []
    end

    test "returns empty list when no entities have both backdrop and description" do
      movie = create_standalone_movie(%{name: "Plain Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      assert Library.list_hero_candidates() == []
    end

    test "returns entities with backdrop image and description with required shape" do
      movie = create_standalone_movie(%{name: "Sample Movie", description: "A sample synopsis"})
      record_present(create_linked_file(%{movie_id: movie.id}))

      create_image(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg",
        extension: "jpg"
      })

      results = Library.list_hero_candidates()

      assert length(results) == 1
      row = hd(results)
      assert row.id == movie.id
      assert row.name == "Sample Movie"
      assert Map.has_key?(row, :year)
      assert Map.has_key?(row, :runtime_minutes)
      assert Map.has_key?(row, :genres)
      assert Map.has_key?(row, :overview)
      assert Map.has_key?(row, :backdrop_url)
      assert row.overview == "A sample synopsis"
    end

    test "includes an eligible tv series (backdrop + description + present file)" do
      series = create_tv_series(%{name: "Hero Series", description: "A series synopsis"})
      create_linked_file(%{tv_series_id: series.id})

      create_image(%{
        tv_series_id: series.id,
        role: "backdrop",
        content_url: "#{series.id}/backdrop.jpg",
        extension: "jpg"
      })

      row = Enum.find(Library.list_hero_candidates(), &(&1.id == series.id))
      assert row, "expected the eligible tv series to appear as a hero candidate"
      assert row.overview == "A series synopsis"
    end

    test "includes an eligible collection member movie, never the collection" do
      # UIDR-025: the hero features movies on their own art and synopsis;
      # the collection entity is not a candidate even when eligible.
      ms = create_movie_series(%{name: "Hero Trilogy", description: "A trilogy synopsis"})

      part1 =
        create_movie(%{
          movie_series_id: ms.id,
          name: "Hero Part 1",
          description: "A member synopsis",
          position: 0
        })

      part2 = create_movie(%{movie_series_id: ms.id, name: "Hero Part 2", position: 1})
      create_linked_file(%{movie_id: part1.id})
      create_linked_file(%{movie_id: part2.id})

      create_image(%{
        movie_series_id: ms.id,
        role: "backdrop",
        content_url: "#{ms.id}/backdrop.jpg",
        extension: "jpg"
      })

      create_image(%{
        movie_id: part1.id,
        role: "backdrop",
        content_url: "#{part1.id}/backdrop.jpg",
        extension: "jpg"
      })

      candidates = Library.list_hero_candidates()

      assert Enum.any?(candidates, &(&1.id == part1.id)),
             "expected the eligible member movie to appear as a hero candidate"

      refute Enum.any?(candidates, &(&1.id == ms.id)),
             "expected the collection container to be absent from hero candidates"
    end

    test "includes an eligible video object" do
      video =
        create_video_object(%{
          name: "Hero Video",
          description: "A video synopsis",
          content_url: "/media/hero-video.mkv"
        })

      create_image(%{
        video_object_id: video.id,
        role: "backdrop",
        content_url: "#{video.id}/backdrop.jpg",
        extension: "jpg"
      })

      assert Enum.any?(Library.list_hero_candidates(), &(&1.id == video.id)),
             "expected the eligible video object to appear as a hero candidate"
    end

    test "does not return entities without a backdrop image" do
      movie =
        create_standalone_movie(%{name: "No Backdrop", description: "Has overview but no backdrop"})

      record_present(create_linked_file(%{movie_id: movie.id}))
      assert Library.list_hero_candidates() == []
    end

    test "issues at most 8 queries regardless of library size" do
      for index <- 1..30 do
        movie = create_standalone_movie(%{name: "Movie #{index}", description: "Some description"})

        create_image(%{
          movie_id: movie.id,
          role: "backdrop",
          content_url: "#{movie.id}/backdrop.jpg",
          extension: "jpg"
        })
      end

      query_count = count_queries(fn -> Library.list_hero_candidates(limit: 12) end)
      assert query_count <= 8, "Expected at most 8 queries, got #{query_count}"
    end

    test "returns every eligible entity when no limit is given" do
      for index <- 1..15 do
        movie = create_standalone_movie(%{name: "Movie #{index}", description: "A synopsis"})
        record_present(create_linked_file(%{movie_id: movie.id}))

        create_image(%{
          movie_id: movie.id,
          role: "backdrop",
          content_url: "#{movie.id}/backdrop.jpg",
          extension: "jpg"
        })
      end

      assert length(Library.list_hero_candidates()) == 15
    end
  end

  # ---------------------------------------------------------------------------
  # Orphan-filtering regression tests
  # Orphan = entity with no linked watched file. These leaked into the dev DB
  # on Apr 17 via the showcase seeder and surfaced in HomeLive rows.
  # ---------------------------------------------------------------------------

  describe "list_recently_added/1 orphan filtering" do
    test "excludes orphan movies (no watched_file)" do
      with_file = create_standalone_movie(%{name: "Real Movie"})
      record_present(create_linked_file(%{movie_id: with_file.id}))

      _orphan = create_standalone_movie(%{name: "Orphan Movie"})

      results = Library.list_recently_added(limit: 10)
      names = Enum.map(results, & &1.name)

      assert "Real Movie" in names
      refute "Orphan Movie" in names
    end

    test "excludes orphan tv series (no watched_file)" do
      with_file = create_tv_series(%{name: "Real Series"})
      record_present(create_linked_file(%{tv_series_id: with_file.id}))

      _orphan = create_tv_series(%{name: "Orphan Series"})

      results = Library.list_recently_added(limit: 10)
      names = Enum.map(results, & &1.name)

      assert "Real Series" in names
      refute "Orphan Series" in names
    end
  end

  describe "list_recently_added/1 collection hoist" do
    test "single-child movie_series surfaces as the child movie, not the collection" do
      ms = create_movie_series(%{name: "Mascot Collection"})
      child = create_movie(%{movie_series_id: ms.id, name: "Mascot Cosmos", position: 0})
      record_present(create_linked_file(%{movie_id: child.id}))

      results = Library.list_recently_added(limit: 10)

      hoisted = Enum.find(results, fn r -> r.name == "Mascot Cosmos" end)
      assert hoisted, "expected the child movie to be present in results"
      assert hoisted.id == child.id

      refute Enum.any?(results, fn r -> r.name == "Mascot Collection" end),
             "expected the singleton collection container to be hidden, but it appeared"
    end

    test "multi-child collection members appear individually; the collection never does" do
      # UIDR-025: what was added is a movie. The collection entity is a
      # filing surface (library view, modal rail), not an activity row.
      ms = create_movie_series(%{name: "Trilogy Collection"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Trilogy Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Trilogy Part 2", position: 1})
      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      results = Library.list_recently_added(limit: 10)

      result_ids = Enum.map(results, & &1.id)
      assert part1.id in result_ids
      assert part2.id in result_ids

      refute Enum.any?(results, fn r -> r.id == ms.id end),
             "expected the collection container to be absent, but it appeared"
    end
  end

  describe "list_in_progress/1 keeps absent-file titles in Continue Watching" do
    # Continue Watching is the user's mental list of "things I'm watching".
    # An absent file does not erase that intent. The hoist
    # categorization is presence-agnostic on this surface (by Movie record
    # count) so transient file-presence changes don't shuffle rows in or out.
    test "includes orphan movies with watch_progress when no file is present" do
      orphan = create_standalone_movie(%{name: "Orphan With Progress"})
      create_watch_progress(%{movie_id: orphan.id, position_seconds: 30.0, duration_seconds: 100.0})

      results = Library.list_in_progress(limit: 10)
      assert Enum.any?(results, &(&1.entity_name == "Orphan With Progress"))
    end

    test "includes a TV series whose watched episodes are all completed but not every episode is watched" do
      # Mirrors how `LibraryProgress.in_progress?/1` reads a series:
      # episodes_completed (1) < episodes_total (3) → in progress, even
      # though the user is not currently mid-episode anywhere.
      series = create_tv_series(%{name: "Half-Watched Show"})
      record_present(create_linked_file(%{tv_series_id: series.id}))
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})

      [ep1, _ep2, _ep3] =
        for ep_num <- 1..3 do
          create_episode(%{
            season_id: season.id,
            episode_number: ep_num,
            name: "S1E#{ep_num}",
            content_url: "/media/test/half-watched-s01e#{ep_num}.mkv"
          })
        end

      create_watch_progress(%{
        episode_id: ep1.id,
        position_seconds: 60.0,
        duration_seconds: 60.0,
        completed: true
      })

      results = Library.list_in_progress(limit: 10)
      assert Enum.any?(results, &(&1.entity_name == "Half-Watched Show"))
    end

    test "excludes a TV series where every episode is completed" do
      # Per Library Schema v2 Phase 2 Task B, a WatchedFile attaches to
      # an Episode-level PlayableItem rather than a TVSeries. Set up
      # season + episodes explicitly so the file-presence row attaches
      # to a real Episode that the in-progress query reasons about.
      series = create_tv_series(%{name: "Fully Watched Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})

      for ep_num <- 1..2 do
        episode =
          create_episode(%{
            season_id: season.id,
            episode_number: ep_num,
            name: "S1E#{ep_num}",
            content_url: "/media/test/fully-watched-s01e#{ep_num}.mkv"
          })

        playable_item = create_playable_item_for_episode(episode)

        record_present(
          create_linked_file(%{
            playable_item_id: playable_item.id,
            file_path: episode.content_url
          })
        )

        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 60.0,
          duration_seconds: 60.0,
          completed: true
        })
      end

      results = Library.list_in_progress(limit: 10)
      refute Enum.any?(results, &(&1.entity_name == "Fully Watched Show"))
    end
  end

  describe "list_in_progress/1 collection hoist" do
    test "single-child movie_series with in-progress child surfaces as the child movie" do
      ms = create_movie_series(%{name: "Mascot Collection"})
      child = create_movie(%{movie_series_id: ms.id, name: "Mascot Cosmos", position: 0})
      record_present(create_linked_file(%{movie_id: child.id}))

      create_watch_progress(%{
        movie_id: child.id,
        position_seconds: 100.0,
        duration_seconds: 1000.0,
        completed: false
      })

      results = Library.list_in_progress(limit: 10)

      hoisted = Enum.find(results, fn r -> r.entity_name == "Mascot Cosmos" end)
      assert hoisted, "expected the child movie to surface in Continue Watching"
      assert hoisted.entity_id == child.id

      refute Enum.any?(results, fn r -> r.entity_name == "Mascot Collection" end),
             "expected the singleton collection container to be hidden, but it appeared"
    end

    test "includes hoisted singleton-collection movies with watch_progress even when file is absent" do
      ms = create_movie_series(%{name: "Mascot Collection"})
      child = create_movie(%{movie_series_id: ms.id, name: "Mascot Cosmos"})
      # No present file — the file is absent / never imported
      create_watch_progress(%{
        movie_id: child.id,
        position_seconds: 100.0,
        duration_seconds: 1000.0,
        completed: false
      })

      results = MediaCentaur.Library.list_in_progress(limit: 50)

      assert Enum.any?(results, &(&1.entity_name == "Mascot Cosmos"))
      refute Enum.any?(results, &(&1.entity_name == "Mascot Collection"))
    end
  end

  describe "list_hero_candidates/1 orphan filtering" do
    test "excludes orphan movies even with backdrop and description" do
      orphan =
        create_standalone_movie(%{
          name: "Orphan With Hero Metadata",
          description: "A description"
        })

      create_image(%{
        movie_id: orphan.id,
        role: "backdrop",
        content_url: "#{orphan.id}/backdrop.jpg",
        extension: "jpg"
      })

      results = Library.list_hero_candidates(limit: 10)
      refute Enum.any?(results, &(&1.name == "Orphan With Hero Metadata"))
    end
  end

  describe "list_hero_candidates/1 collection hoist" do
    test "single-child movie_series surfaces as the child movie, not the collection" do
      ms = create_movie_series(%{name: "Mascot Collection"})

      child =
        create_movie(%{
          movie_series_id: ms.id,
          name: "Mascot Cosmos",
          position: 0,
          description: "A space-faring plumber adventure",
          date_published: ~D[2007-11-01]
        })

      record_present(create_linked_file(%{movie_id: child.id}))

      create_image(%{
        movie_id: child.id,
        role: "backdrop",
        content_url: "#{child.id}/backdrop.jpg",
        extension: "jpg"
      })

      results = Library.list_hero_candidates(limit: 10)

      hoisted = Enum.find(results, fn r -> r.name == "Mascot Cosmos" end)
      assert hoisted, "expected the child movie to surface as a hero candidate"
      assert hoisted.id == child.id

      refute Enum.any?(results, fn r -> r.name == "Mascot Collection" end),
             "expected the singleton collection container to be hidden, but it appeared"
    end
  end

  describe "load_modal_entry/1" do
    test "returns shaped entry for a standalone movie with extras populated" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))

      create_extra(%{movie_id: movie.id, name: "Behind the Scenes", kind: :featurette})

      assert {:ok, entry} = Library.ModalEntry.load(movie.id)
      assert entry.entity.id == movie.id
      assert entry.entity.type == :movie
      assert Enum.map(entry.entity.extras, & &1.name) == ["Behind the Scenes"]
      # No watch_progress yet, so summary is nil — but the key exists.
      assert Map.has_key?(entry, :progress)
      assert is_list(entry.progress_records)
    end

    test "returns shaped entry for a TV series with season-level extras" do
      # Per Library Schema v2 Phase 2 Task B the WatchedFile attaches
      # to an Episode-level PlayableItem; create the episode and its
      # PlayableItem before linking the file.
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "S1E1",
          content_url: "/media/test/sample-show-s01e01.mkv"
        })

      playable_item = create_playable_item_for_episode(episode)

      record_present(
        create_linked_file(%{
          playable_item_id: playable_item.id,
          file_path: episode.content_url
        })
      )

      create_extra(%{tv_series_id: series.id, name: "Series Trailer", kind: :trailer})
      create_extra(%{season_id: season.id, name: "Season Recap", kind: :featurette})

      assert {:ok, entry} = Library.ModalEntry.load(series.id)
      assert entry.entity.id == series.id
      assert entry.entity.type == :tv_series
      assert Enum.map(entry.entity.extras, & &1.name) == ["Series Trailer"]

      [loaded_season] = entry.entity.seasons
      assert Enum.map(loaded_season.extras, & &1.name) == ["Season Recap"]
    end

    test "returns shaped entry for a movie series" do
      series = create_movie_series(%{name: "Sample Saga"})

      part1 =
        Library.Containers.create!(:movie, %{
          name: "Saga Part 1",
          movie_series_id: series.id,
          position: 0
        })

      part2 =
        Library.Containers.create!(:movie, %{
          name: "Saga Part 2",
          movie_series_id: series.id,
          position: 1
        })

      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      assert {:ok, entry} = Library.ModalEntry.load(series.id)
      assert entry.entity.id == series.id
    end

    test "returns shaped entry for a video object" do
      video = create_video_object(%{name: "Sample Clip"})
      record_present(create_linked_file(%{video_object_id: video.id}))

      assert {:ok, entry} = Library.ModalEntry.load(video.id)
      assert entry.entity.id == video.id
      assert entry.entity.type == :video_object
    end

    test "returns :not_found for a missing UUID" do
      assert Library.ModalEntry.load(Ecto.UUID.generate()) == :not_found
    end

    test "returns :not_found when no file is present for the entity" do
      orphan = create_standalone_movie(%{name: "Orphan"})
      assert Library.ModalEntry.load(orphan.id) == :not_found
    end

    test "issues a bounded number of queries (no N+1 regression)" do
      series = create_tv_series(%{name: "Bounded Query Show"})
      record_present(create_linked_file(%{tv_series_id: series.id}))

      for season_num <- 1..3 do
        season =
          create_season(%{
            tv_series_id: series.id,
            season_number: season_num,
            name: "S#{season_num}"
          })

        for ep_num <- 1..5 do
          create_episode(%{
            season_id: season.id,
            episode_number: ep_num,
            name: "S#{season_num}E#{ep_num}"
          })
        end
      end

      # Phase 3.2 Task D: warm the projection so the test measures the
      # production-warm path (Pillar-2 ETS reads) rather than the
      # test-mode DB-fallback cost. Without the warm-up, every modal
      # open rebuilds the canonical leaf from DB (~7 queries that don't
      # scale with episode count — bounded, but noise for an N+1 check).
      :ok = MediaCentaur.Library.Views.Detail.refresh_cache()

      on_exit(fn ->
        case :ets.whereis(:library_view_detail) do
          :undefined -> :ok
          _ -> :ets.delete(:library_view_detail)
        end
      end)

      query_count = count_queries(fn -> Library.ModalEntry.load(series.id) end)

      # Projection-warm path: ETS lookup (0 queries) + 1 progress query.
      # Bound at 5 to leave room for incidental queries; cap is well
      # below any N+1 explosion (which would scale with the 15-episode
      # fixture).
      assert query_count <= 5,
             "Expected ≤5 queries, got #{query_count} — possible N+1 regression"
    end
  end

  describe "playable_file_path/1" do
    test "returns the present-on-disk file path for the PlayableItem" do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      playable_item = create_playable_item_for_movie(movie)

      file =
        create_linked_file(%{
          playable_item_id: playable_item.id,
          file_path: "/media/sample-movie.mkv"
        })

      record_present(file)

      assert Library.Files.playable_file_path(playable_item.id) == "/media/sample-movie.mkv"
    end

    test "returns nil when the PlayableItem has no WatchedFile" do
      movie = create_standalone_movie(%{name: "No File"})
      playable_item = create_playable_item_for_movie(movie)

      assert Library.Files.playable_file_path(playable_item.id) == nil
    end

    test "returns nil when the WatchedFile has been removed" do
      # Post-Phase-4 (library-presence-unification): "absence" is now
      # structural — no WatchedFile means absent. Per ADR-046, the
      # application drives cascade cleanup via FileEventHandler before
      # dropping the FilePresence row.
      movie = create_standalone_movie(%{name: "Absent File"})
      playable_item = create_playable_item_for_movie(movie)

      file =
        create_linked_file(%{
          playable_item_id: playable_item.id,
          file_path: "/media/absent.mkv"
        })

      MediaCentaur.Library.FileEventHandler.cleanup_removed_files([file.file_path])
      MediaCentaur.Library.FilePresence.delete_paths([file.file_path])

      assert Library.Files.playable_file_path(playable_item.id) == nil
    end

    test "returns nil for an unknown PlayableItem id" do
      assert Library.Files.playable_file_path(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_progress_records_for_tv_series/1 (Phase 3.2 Task C.2)" do
    # Helper used by `SeriesDetail.compose/1` to thread per-episode
    # WatchProgress to `build/4` after the projection flip. Returns the
    # same shape `EntityShape.extract_progress(_, :tv_series)` produced
    # for the legacy path — each record carries a synthesised
    # `:playable_item` so `EpisodeList.progress_container_id/1` resolves
    # to the Episode UUID.

    alias MediaCentaur.Library.EpisodeList

    test "returns [] for a series with no episodes" do
      tv = create_tv_series(%{name: "Empty Series"})
      assert Library.ProgressRecords.list_for_tv_series(tv.id) == []
    end

    test "returns [] for episodes without WatchProgress" do
      tv = create_tv_series(%{name: "Unwatched Series"})
      season = create_season(%{tv_series_id: tv.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1, name: "S1E1"})
      _playable_item = create_playable_item_for_episode(episode)

      assert Library.ProgressRecords.list_for_tv_series(tv.id) == []
    end

    test "returns one record per episode with progress, keyed via :playable_item.container_id" do
      tv = create_tv_series(%{name: "Progress Series"})
      season = create_season(%{tv_series_id: tv.id, season_number: 1})

      episode1 = create_episode(%{season_id: season.id, episode_number: 1, name: "S1E1"})
      episode2 = create_episode(%{season_id: season.id, episode_number: 2, name: "S1E2"})
      _playable1 = create_playable_item_for_episode(episode1)
      _playable2 = create_playable_item_for_episode(episode2)

      create_watch_progress(%{episode_id: episode1.id, completed: true})
      create_watch_progress(%{episode_id: episode2.id, position_seconds: 120.0})

      records = Library.ProgressRecords.list_for_tv_series(tv.id)

      assert length(records) == 2

      episode_ids = Enum.map(records, &EpisodeList.progress_container_id/1)
      assert Enum.sort(episode_ids) == Enum.sort([episode1.id, episode2.id])

      completed = Enum.find(records, & &1.completed)
      assert EpisodeList.progress_container_id(completed) == episode1.id
    end

    test "ignores progress on episodes of other series" do
      tv_a = create_tv_series(%{name: "Series A"})
      tv_b = create_tv_series(%{name: "Series B"})

      season_a = create_season(%{tv_series_id: tv_a.id, season_number: 1})
      season_b = create_season(%{tv_series_id: tv_b.id, season_number: 1})

      episode_a = create_episode(%{season_id: season_a.id, episode_number: 1, name: "A1"})
      episode_b = create_episode(%{season_id: season_b.id, episode_number: 1, name: "B1"})
      _pa = create_playable_item_for_episode(episode_a)
      _pb = create_playable_item_for_episode(episode_b)

      create_watch_progress(%{episode_id: episode_a.id, completed: true})
      create_watch_progress(%{episode_id: episode_b.id, completed: true})

      records = Library.ProgressRecords.list_for_tv_series(tv_a.id)

      assert [record] = records
      assert EpisodeList.progress_container_id(record) == episode_a.id
    end

    test "returns [] for an unknown TVSeries id" do
      assert Library.ProgressRecords.list_for_tv_series(Ecto.UUID.generate()) == []
    end
  end

  # Regression: the Library Schema v2 table rename
  # (`seasons` → `library_seasons`) dropped the
  # `(entity_id, season_number)` unique index and never re-created it on
  # the new `tv_series_id` column. With no DB guard, a burst of episodes
  # for one new season races in `find_or_insert_by/3` and inserts
  # duplicate `Season` rows; every later `Repo.get_by` then raises
  # `MultipleResultsError`, wedging the whole series. Episodes kept their
  # index across the rename, so they never duplicated — but their
  # changeset still lacks the `unique_constraint`, so a racing insert
  # raises `ConstraintError` instead of returning a tidy `{:error, _}`.
  describe "season uniqueness" do
    test "create_season/1 rejects a duplicate (tv_series_id, season_number)" do
      series = create_tv_series(%{name: "Dup Season Show"})

      assert {:ok, _season} =
               Library.Seasons.create(%{tv_series_id: series.id, season_number: 3, name: "S3"})

      assert {:error, changeset} =
               Library.Seasons.create(%{tv_series_id: series.id, season_number: 3, name: "S3 again"})

      refute changeset.valid?
      assert "has already been taken" in all_error_messages(changeset)
      assert length(Library.Seasons.list_for_tv_series(series.id)) == 1
    end

    test "find_or_create_season_for_tv_series/1 is idempotent — repeated calls yield one season" do
      series = create_tv_series(%{name: "Idempotent Season Show"})
      attrs = %{tv_series_id: series.id, season_number: 1, name: "S1", number_of_episodes: 10}

      assert {:ok, first} = Library.Seasons.find_or_create(attrs)
      assert {:ok, second} = Library.Seasons.find_or_create(attrs)

      assert first.id == second.id
      assert length(Library.Seasons.list_for_tv_series(series.id)) == 1
    end
  end

  describe "episode uniqueness" do
    test "create_episode/1 returns {:error, changeset} (not a raised ConstraintError) on a duplicate (season_id, episode_number)" do
      series = create_tv_series(%{name: "Dup Episode Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})

      assert {:ok, _episode} =
               Library.Episodes.create(%{season_id: season.id, episode_number: 1, name: "Pilot"})

      assert {:error, changeset} =
               Library.Episodes.create(%{season_id: season.id, episode_number: 1, name: "Pilot again"})

      refute changeset.valid?
      assert "has already been taken" in all_error_messages(changeset)
      assert length(Library.Episodes.list_for_season(season.id)) == 1
    end

    test "find_or_create_episode/1 is idempotent — repeated calls yield one episode" do
      series = create_tv_series(%{name: "Idempotent Episode Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})
      attrs = %{season_id: season.id, episode_number: 5, name: "E5"}

      assert {:ok, first} = Library.Episodes.find_or_create(attrs)
      assert {:ok, second} = Library.Episodes.find_or_create(attrs)

      assert first.id == second.id
      assert length(Library.Episodes.list_for_season(season.id)) == 1
    end
  end

  describe "stats/0" do
    test "counts entities by type, episodes, files, and images" do
      movie = create_standalone_movie(%{name: "Standalone Movie"})
      series = create_tv_series(%{name: "A Show"})
      create_movie_series(%{name: "A Collection"})
      create_video_object(%{name: "A Clip"})

      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})
      create_episode(%{season_id: season.id, episode_number: 1, name: "E1"})
      create_episode(%{season_id: season.id, episode_number: 2, name: "E2"})

      create_linked_file(%{movie_id: movie.id})

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      stats = Library.Stats.all()

      assert stats.by_type == %{movie: 1, tv_series: 1, movie_series: 1, video_object: 1}
      assert stats.episodes == 2
      assert stats.files == 1
      assert stats.images == 1
    end

    test "a movie belonging to a movie series is not counted as a standalone movie" do
      collection = create_movie_series(%{name: "Trilogy"})
      create_movie(%{name: "Part One", movie_series_id: collection.id})

      stats = Library.Stats.all()

      assert stats.by_type.movie == 0
      assert stats.by_type.movie_series == 1
    end
  end

  describe "watched_file_paths_under/1" do
    test "returns paths of already-imported files that live under a directory" do
      movie = create_movie(%{name: "Under Dir Movie"})

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/movies/Some Release/movie.mkv",
        media_dir: "/media/movies"
      })

      assert Library.Files.paths_under("/media/movies/Some Release") == [
               "/media/movies/Some Release/movie.mkv"
             ]
    end

    test "does not match a sibling directory with a similar name prefix" do
      movie = create_movie(%{name: "Sibling Dir Movie"})

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/movies/Some Release Extended/movie.mkv",
        media_dir: "/media/movies"
      })

      assert Library.Files.paths_under("/media/movies/Some Release") == []
    end

    test "returns an empty list when nothing lives under the directory" do
      assert Library.Files.paths_under("/media/movies/Nothing Here") == []
    end
  end

  defp all_error_messages(changeset) do
    changeset |> errors_on() |> Map.values() |> List.flatten()
  end
end
