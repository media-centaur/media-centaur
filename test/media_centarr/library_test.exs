defmodule MediaCentarr.LibraryTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory
  alias MediaCentarr.Library

  # Records the file as present in watcher_files so Browser queries include it.

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

  # Post-Phase-7 no-op (legacy hook from the library-presence-unification campaign).
  defp record_present(_file), do: :ok

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

    test "multi-child movie_series stays as a collection row" do
      ms = create_movie_series(%{name: "Trilogy Collection"})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Trilogy Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Trilogy Part 2", position: 1})
      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      results = Library.list_recently_added(limit: 10)

      collection = Enum.find(results, fn r -> r.name == "Trilogy Collection" end)
      assert collection, "expected the multi-child collection to appear in results"
      assert collection.id == ms.id
    end
  end

  describe "list_in_progress/1 mirrors the /library?in_progress=1 surface" do
    # Continue Watching is the user's mental list of "things I'm watching".
    # An absent file does not erase that intent — and matching this query to
    # the broader `/library?in_progress=1` filter (which only checks for
    # incomplete progress) keeps the two surfaces consistent. The hoist
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
          create_episode(%{season_id: season.id, episode_number: ep_num, name: "S1E#{ep_num}"})
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

      results = MediaCentarr.Library.list_in_progress(limit: 50)

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

      assert {:ok, entry} = Library.load_modal_entry(movie.id)
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

      assert {:ok, entry} = Library.load_modal_entry(series.id)
      assert entry.entity.id == series.id
      assert entry.entity.type == :tv_series
      assert Enum.map(entry.entity.extras, & &1.name) == ["Series Trailer"]

      [loaded_season] = entry.entity.seasons
      assert Enum.map(loaded_season.extras, & &1.name) == ["Season Recap"]
    end

    test "returns shaped entry for a movie series" do
      series = create_movie_series(%{name: "Sample Saga"})

      part1 =
        Library.create_movie!(%{name: "Saga Part 1", movie_series_id: series.id, position: 0})

      part2 =
        Library.create_movie!(%{name: "Saga Part 2", movie_series_id: series.id, position: 1})

      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      assert {:ok, entry} = Library.load_modal_entry(series.id)
      assert entry.entity.id == series.id
    end

    test "returns shaped entry for a video object" do
      video = create_video_object(%{name: "Sample Clip"})
      record_present(create_linked_file(%{video_object_id: video.id}))

      assert {:ok, entry} = Library.load_modal_entry(video.id)
      assert entry.entity.id == video.id
      assert entry.entity.type == :video_object
    end

    test "returns :not_found for a missing UUID" do
      assert Library.load_modal_entry(Ecto.UUID.generate()) == :not_found
    end

    test "returns :not_found when no file is present for the entity" do
      orphan = create_standalone_movie(%{name: "Orphan"})
      assert Library.load_modal_entry(orphan.id) == :not_found
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
      :ok = MediaCentarr.Library.Views.Detail.refresh_cache()

      on_exit(fn ->
        case :ets.whereis(:library_view_detail) do
          :undefined -> :ok
          _ -> :ets.delete(:library_view_detail)
        end
      end)

      query_count = count_queries(fn -> Library.load_modal_entry(series.id) end)

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

      assert Library.playable_file_path(playable_item.id) == "/media/sample-movie.mkv"
    end

    test "returns nil when the PlayableItem has no WatchedFile" do
      movie = create_standalone_movie(%{name: "No File"})
      playable_item = create_playable_item_for_movie(movie)

      assert Library.playable_file_path(playable_item.id) == nil
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

      MediaCentarr.Library.FileEventHandler.cleanup_removed_files([file.file_path])
      MediaCentarr.Library.FilePresence.delete_paths([file.file_path])

      assert Library.playable_file_path(playable_item.id) == nil
    end

    test "returns nil for an unknown PlayableItem id" do
      assert Library.playable_file_path(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_progress_records_for_tv_series/1 (Phase 3.2 Task C.2)" do
    # Helper used by `SeriesDetail.compose/1` to thread per-episode
    # WatchProgress to `build/4` after the projection flip. Returns the
    # same shape `EntityShape.extract_progress(_, :tv_series)` produced
    # for the legacy path — each record carries a synthesised
    # `:playable_item` so `EpisodeList.progress_container_id/1` resolves
    # to the Episode UUID.

    alias MediaCentarr.Library.EpisodeList

    test "returns [] for a series with no episodes" do
      tv = create_tv_series(%{name: "Empty Series"})
      assert Library.list_progress_records_for_tv_series(tv.id) == []
    end

    test "returns [] for episodes without WatchProgress" do
      tv = create_tv_series(%{name: "Unwatched Series"})
      season = create_season(%{tv_series_id: tv.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1, name: "S1E1"})
      _playable_item = create_playable_item_for_episode(episode)

      assert Library.list_progress_records_for_tv_series(tv.id) == []
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

      records = Library.list_progress_records_for_tv_series(tv.id)

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

      records = Library.list_progress_records_for_tv_series(tv_a.id)

      assert [record] = records
      assert EpisodeList.progress_container_id(record) == episode_a.id
    end

    test "returns [] for an unknown TVSeries id" do
      assert Library.list_progress_records_for_tv_series(Ecto.UUID.generate()) == []
    end
  end
end
