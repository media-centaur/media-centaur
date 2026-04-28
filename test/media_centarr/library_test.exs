defmodule MediaCentarr.LibraryTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory
  alias MediaCentarr.Library
  alias MediaCentarr.Watcher.FilePresence

  # Records the file as present in watcher_files so Browser queries include it.
  defp record_present(file), do: FilePresence.record_file(file.file_path, file.watch_dir)

  defp count_queries(fun) do
    ref = make_ref()
    parent = self()
    handler_id = {:library_query_count, ref}

    :ok =
      :telemetry.attach(
        handler_id,
        [:media_centarr, :repo, :query],
        fn _, _, _, _ -> send(parent, {:query, ref}) end,
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
      assert is_binary(row.last_episode_label) or is_nil(row.last_episode_label)
      assert is_integer(row.progress_pct)
      assert row.progress_pct >= 0 and row.progress_pct <= 100
      assert Map.has_key?(row, :backdrop_url)
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
            name: "S1E#{episode_number}"
          })

        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 10.0,
          duration_seconds: 60.0
        })
      end
    end
  end

  describe "list_recently_added/1" do
    test "returns empty list when no entities exist" do
      assert Library.list_recently_added() == []
    end

    test "returns recently added movies with required shape" do
      movie = create_standalone_movie(%{name: "Sample Movie Fourteen"})
      record_present(create_linked_file(%{movie_id: movie.id}))
      results = Library.list_recently_added()

      assert length(results) == 1
      row = hd(results)
      assert row.id == movie.id
      assert row.name == "Sample Movie Fourteen"
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
      movie = create_standalone_movie(%{name: "Inception", description: "A thief who steals secrets"})
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
      assert row.name == "Inception"
      assert Map.has_key?(row, :year)
      assert Map.has_key?(row, :runtime_minutes)
      assert Map.has_key?(row, :genres)
      assert Map.has_key?(row, :overview)
      assert Map.has_key?(row, :backdrop_url)
      assert row.overview == "A thief who steals secrets"
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

  describe "list_in_progress/1 orphan filtering" do
    test "excludes orphan movies even with watch_progress" do
      orphan = create_standalone_movie(%{name: "Orphan With Progress"})
      create_watch_progress(%{movie_id: orphan.id, position_seconds: 30.0, duration_seconds: 100.0})

      results = Library.list_in_progress(limit: 10)
      refute Enum.any?(results, &(&1.entity_name == "Orphan With Progress"))
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
end
