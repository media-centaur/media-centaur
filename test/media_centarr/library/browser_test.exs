defmodule MediaCentarr.Library.BrowserTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.Browser
  alias MediaCentarr.Watcher.FilePresence

  # Creates a linked file and registers it as present in watcher_files,
  # which the typed queries require for the EXISTS join.
  defp create_present_file(attrs) do
    file = create_linked_file(attrs)
    FilePresence.record_file(file.file_path, file.watch_dir)
    file
  end

  describe "fetch_all_typed_entries/0" do
    test "includes a standalone movie with a linked file" do
      movie = create_standalone_movie(%{name: "Standalone Movie"})
      create_present_file(%{movie_id: movie.id})

      results = Browser.fetch_all_typed_entries()

      assert [%{entity: fetched, progress: nil}] = results
      assert fetched.id == movie.id
      assert fetched.type == :movie
    end

    test "includes a TV series with sorted seasons and episodes" do
      series = create_tv_series(%{name: "Test Show"})
      create_present_file(%{tv_series_id: series.id})

      season2 = create_season(%{tv_series_id: series.id, season_number: 2, name: "Season 2"})
      season1 = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})

      create_episode(%{season_id: season2.id, episode_number: 1, name: "S2E1"})
      create_episode(%{season_id: season1.id, episode_number: 2, name: "S1E2"})
      create_episode(%{season_id: season1.id, episode_number: 1, name: "S1E1"})

      [%{entity: fetched}] = Browser.fetch_all_typed_entries()

      assert fetched.type == :tv_series
      assert [first_season, second_season] = fetched.seasons
      assert first_season.season_number == 1
      assert second_season.season_number == 2

      episode_numbers = Enum.map(first_season.episodes, & &1.episode_number)
      assert episode_numbers == [1, 2]
    end

    test "unwraps a movie_series with a single child into a flat movie" do
      series = create_movie_series(%{name: "Series Name"})
      create_present_file(%{movie_series_id: series.id})
      create_movie(%{movie_series_id: series.id, name: "Only Child", position: 0})

      [%{entity: fetched}] = Browser.fetch_all_typed_entries()

      assert fetched.type == :movie
      assert fetched.name == "Only Child"
      assert fetched.movies == []
    end

    test "preserves a movie_series with multiple children" do
      series = create_movie_series(%{name: "Trilogy"})
      create_present_file(%{movie_series_id: series.id})
      create_movie(%{movie_series_id: series.id, name: "Part 1", position: 0})
      create_movie(%{movie_series_id: series.id, name: "Part 2", position: 1})

      [%{entity: fetched}] = Browser.fetch_all_typed_entries()

      assert fetched.type == :movie_series
      assert fetched.name == "Trilogy"
      assert length(fetched.movies) == 2
    end

    test "excludes entities where all watched files are absent" do
      movie = create_standalone_movie(%{name: "Gone Movie"})
      file = create_present_file(%{movie_id: movie.id})

      FilePresence.mark_files_absent([file.file_path])

      assert [] = Browser.fetch_all_typed_entries()
    end
  end

  describe "fetch_typed_entries_by_ids/1" do
    test "fetches a specific entry by ID" do
      movie = create_standalone_movie(%{name: "Target Movie"})
      create_present_file(%{movie_id: movie.id})

      other = create_standalone_movie(%{name: "Other Movie"})
      create_present_file(%{movie_id: other.id})

      {entries, gone_ids} = Browser.fetch_typed_entries_by_ids([movie.id])

      assert [%{entity: fetched}] = entries
      assert fetched.id == movie.id
      assert MapSet.size(gone_ids) == 0
    end

    test "returns gone_ids for destroyed entries" do
      missing_id = Ecto.UUID.generate()

      {entries, gone_ids} = Browser.fetch_typed_entries_by_ids([missing_id])

      assert entries == []
      assert MapSet.member?(gone_ids, missing_id)
    end

    test "excludes absent entries and includes them in gone_ids" do
      movie = create_standalone_movie(%{name: "Absent Movie"})
      file = create_present_file(%{movie_id: movie.id})

      FilePresence.mark_files_absent([file.file_path])

      {entries, gone_ids} = Browser.fetch_typed_entries_by_ids([movie.id])

      assert entries == []
      assert MapSet.member?(gone_ids, movie.id)
    end
  end

  # Regression guard for the "N+1 queries" claim in the audit backlog.
  #
  # `Library.Browser` uses `Repo.all |> Repo.preload(...)` which issues ONE
  # query per (association, parent type) pair via an `IN` clause. The total
  # cost is a small constant that does NOT scale with the number of rows.
  #
  # Measured: a fixture covering all four types (standalone movie, TV series
  # with seasons/episodes, movie series with children, video object) produces
  # exactly 29 queries. A 14-entity fixture with the same type mix produces
  # exactly the same 29. The ceiling below (32) gives 3 queries of slack for
  # small future additions and is tight enough to catch a real regression
  # (e.g. accidental per-row dispatch from a preload callback) — any change
  # should force a conscious update here.
  describe "query count (N+1 regression guard)" do
    @query_ceiling 32

    # Counts Ecto queries fired while `fun` runs. Attaches a unique-named
    # telemetry handler, drains the resulting messages, and returns
    # `{result, queries}` where `queries` is a list of `{source, sql}`.
    defp count_queries(fun) do
      ref = make_ref()
      parent = self()
      handler_id = {:library_browser_query_count, ref}

      :ok =
        :telemetry.attach(
          handler_id,
          [:media_centarr, :repo, :query],
          fn _event, _measurements, metadata, _config ->
            send(parent, {:query, ref, metadata.source, metadata.query})
          end,
          nil
        )

      try do
        result = fun.()
        queries = drain_queries(ref, [])
        {result, queries}
      after
        :telemetry.detach(handler_id)
      end
    end

    defp drain_queries(ref, acc) do
      receive do
        {:query, ^ref, source, sql} -> drain_queries(ref, [{source, sql} | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    test "fetch_all_typed_entries issues a bounded number of queries (diverse fixture)" do
      # One of every type, with nested associations, to exercise every preload
      # path. This is the upper-bound fixture: all query paths fire.
      movie = create_standalone_movie(%{name: "Standalone"})
      create_present_file(%{movie_id: movie.id})

      series = create_tv_series(%{name: "A Show"})
      create_present_file(%{tv_series_id: series.id})
      season1 = create_season(%{tv_series_id: series.id, season_number: 1, name: "S1"})
      season2 = create_season(%{tv_series_id: series.id, season_number: 2, name: "S2"})
      create_episode(%{season_id: season1.id, episode_number: 1, name: "S1E1"})
      create_episode(%{season_id: season1.id, episode_number: 2, name: "S1E2"})
      create_episode(%{season_id: season2.id, episode_number: 1, name: "S2E1"})

      collection = create_movie_series(%{name: "Trilogy"})
      create_present_file(%{movie_series_id: collection.id})
      create_movie(%{movie_series_id: collection.id, name: "Part 1", position: 0})
      create_movie(%{movie_series_id: collection.id, name: "Part 2", position: 1})

      video = create_video_object(%{name: "A Clip"})
      create_present_file(%{video_object_id: video.id})

      {entries, queries} = count_queries(fn -> Browser.fetch_all_typed_entries() end)

      assert length(entries) >= 4,
             "expected at least 4 entries, got #{length(entries)}"

      assert length(queries) <= @query_ceiling,
             "expected <= #{@query_ceiling} queries, got #{length(queries)}. " <>
               "Sources: #{inspect(Enum.frequencies(Enum.map(queries, fn {src, _} -> src end)))}"
    end

    test "fetch_all_typed_entries query count does NOT scale with row count (the actual N+1 guard)" do
      # Same type mix as the diverse fixture above but many more rows. If the
      # query count is constant in the number of rows, there is no N+1. If it
      # scales linearly, this ceiling will blow and the regression is caught.
      for n <- 1..5 do
        movie = create_standalone_movie(%{name: "Movie #{n}"})
        create_present_file(%{movie_id: movie.id})
      end

      for n <- 1..3 do
        series = create_tv_series(%{name: "Show #{n}"})
        create_present_file(%{tv_series_id: series.id})

        for season_number <- 1..2 do
          season =
            create_season(%{
              tv_series_id: series.id,
              season_number: season_number,
              name: "S#{season_number}"
            })

          for episode_number <- 1..4 do
            create_episode(%{
              season_id: season.id,
              episode_number: episode_number,
              name: "E#{episode_number}"
            })
          end
        end
      end

      for n <- 1..2 do
        collection = create_movie_series(%{name: "Collection #{n}"})
        create_present_file(%{movie_series_id: collection.id})

        for part <- 1..3 do
          create_movie(%{
            movie_series_id: collection.id,
            name: "C#{n} P#{part}",
            position: part - 1
          })
        end
      end

      for n <- 1..4 do
        video = create_video_object(%{name: "Clip #{n}"})
        create_present_file(%{video_object_id: video.id})
      end

      {entries, queries} = count_queries(fn -> Browser.fetch_all_typed_entries() end)

      # 5 standalone movies + 3 TV series + 2 movie series + 4 video objects = 14
      assert length(entries) == 14

      assert length(queries) <= @query_ceiling,
             "expected <= #{@query_ceiling} queries even with a 14-entity fixture, " <>
               "got #{length(queries)}. If this count scales with row count, the " <>
               "preload strategy has regressed into N+1. " <>
               "Sources: #{inspect(Enum.frequencies(Enum.map(queries, fn {src, _} -> src end)))}"
    end
  end
end
