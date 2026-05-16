defmodule MediaCentarr.Library.Views.SearchTest do
  @moduledoc """
  Spec tests for the `Library.Views.Search` ETS-backed projection
  (ADR-041, Library Schema v2 Phase 3 Task C).

  Tests through the public read API only — `Library.Views.search/2`
  and `Search.refresh_cache/0`. No `:sys.get_state`, no direct
  `:ets.lookup`, no `GenServer.call` on the worker. PubSub-synchronised
  assertions use the derived `library:views` topic to wait for refresh
  completion.
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library.Events.EntitiesChanged
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.{Search, SearchItem}
  alias MediaCentarr.Topics
  alias MediaCentarr.Watcher.FilePresence

  @table :library_view_search

  defp record_present(file), do: FilePresence.record_file(file.file_path, file.watch_dir)

  defp on_exit_clear_table do
    on_exit(fn ->
      case :ets.whereis(@table) do
        :undefined -> :ok
        _ref -> :ets.delete(@table)
      end
    end)
  end

  defp seed_present_movie(name, overrides \\ %{}) do
    attrs = Map.merge(%{name: name}, overrides)
    movie = create_standalone_movie(attrs)
    record_present(create_linked_file(%{movie_id: movie.id}))
    movie
  end

  defp seed_present_tv_series(name) do
    series = create_tv_series(%{name: name})

    record_present(
      create_linked_file(%{
        tv_series_id: series.id,
        file_path: "/media/test/#{name}.S01E01.mkv"
      })
    )

    series
  end

  defp seed_present_movie_series(name) do
    series = create_movie_series(%{name: name})

    record_present(
      create_linked_file(%{
        movie_series_id: series.id,
        file_path: "/media/test/#{name}.Part1.mkv"
      })
    )

    record_present(
      create_linked_file(%{
        movie_series_id: series.id,
        file_path: "/media/test/#{name}.Part2.mkv"
      })
    )

    series
  end

  defp seed_present_video_object(name) do
    vo = create_video_object(%{name: name})
    record_present(create_linked_file(%{video_object_id: vo.id}))
    vo
  end

  describe "Cache behaviour — relevant?/1" do
    test "accepts library entity-changed events" do
      assert Search.relevant?({:entities_changed, %{entity_ids: ["x"]}})
    end

    test "accepts availability-changed events (drive mount / unmount)" do
      assert Search.relevant?({:availability_changed, "/media/test", :available})
      assert Search.relevant?({:availability_changed, "/media/test", :unavailable})
    end

    test "rejects unrelated messages" do
      refute Search.relevant?(:something_else)
      refute Search.relevant?({:watch_event_created, %{}})
      refute Search.relevant?({:entity_progress_updated, %{}})
      refute Search.relevant?({:other, "payload"})
    end
  end

  describe "cold start — empty / whitespace query" do
    test "returns [] for empty query" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      assert :ok = Search.refresh_cache()

      assert Views.search("") == []
    end

    test "returns [] for whitespace-only query" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      assert :ok = Search.refresh_cache()

      assert Views.search("   ") == []
    end
  end

  describe "cold start — refresh_cache/0 indexes all entity kinds" do
    test "exact name match returns single result with score 1.0" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      seed_present_movie("Movie B")

      assert :ok = Search.refresh_cache()

      results = Views.search("Movie A")
      assert [%SearchItem{name: "Movie A", score: 1.0}] = results
    end

    test "case-insensitive match" do
      on_exit_clear_table()

      seed_present_movie("Movie A")

      assert :ok = Search.refresh_cache()

      assert [%SearchItem{name: "Movie A"}] = Views.search("movie a")
      assert [%SearchItem{name: "Movie A"}] = Views.search("MOVIE A")
    end

    test "prefix match scored above substring match" do
      on_exit_clear_table()

      # "Movie Alpha" starts with "Movie" — prefix.
      # "The Movie Show" contains "Movie" mid-string — substring.
      seed_present_movie("Movie Alpha")
      seed_present_movie("The Movie Show")

      assert :ok = Search.refresh_cache()

      results = Views.search("Movie")
      names = Enum.map(results, & &1.name)

      # Both matched; prefix item sorts first by score.
      assert hd(names) == "Movie Alpha"
      assert "The Movie Show" in names
    end

    test "results sorted by descending score then ascending name (stable for ties)" do
      on_exit_clear_table()

      # Two entries with identical "Movie Z" / "Movie A" — both exact
      # matches for "Movie" prefix, same score; tie-break by name asc.
      seed_present_movie("Movie Z")
      seed_present_movie("Movie A")
      seed_present_movie("Movie M")

      assert :ok = Search.refresh_cache()

      results = Views.search("Movie")
      names = Enum.map(results, & &1.name)

      # All three prefix-match "Movie"; identical prefix score; tie-break
      # alphabetical.
      assert names == ["Movie A", "Movie M", "Movie Z"]
    end

    test "respects :limit option" do
      on_exit_clear_table()

      Enum.each(1..5, fn i -> seed_present_movie("Movie #{i}") end)

      assert :ok = Search.refresh_cache()

      assert length(Views.search("Movie", limit: 3)) == 3
      assert length(Views.search("Movie", limit: 100)) == 5
    end

    test "respects :kind_filter (:movies only)" do
      on_exit_clear_table()

      seed_present_movie("Sample Movie")
      seed_present_tv_series("Sample Show")
      seed_present_video_object("Sample Video")

      assert :ok = Search.refresh_cache()

      results = Views.search("Sample", kind_filter: :movies)
      assert length(results) == 1
      assert hd(results).container_type == :movie
      assert hd(results).name == "Sample Movie"
    end

    test "respects :kind_filter (:tv_series only)" do
      on_exit_clear_table()

      seed_present_movie("Sample Movie")
      seed_present_tv_series("Sample Show A")
      seed_present_tv_series("Sample Show B")

      assert :ok = Search.refresh_cache()

      results = Views.search("Sample", kind_filter: :tv_series)
      assert length(results) == 2
      assert Enum.all?(results, &(&1.container_type == :tv_series))
    end

    test "respects :kind_filter (:movie_series only)" do
      on_exit_clear_table()

      seed_present_movie("Sample Movie")
      seed_present_movie_series("Sample Saga")

      assert :ok = Search.refresh_cache()

      results = Views.search("Sample", kind_filter: :movie_series)
      assert length(results) == 1
      assert hd(results).container_type == :movie_series
    end

    test "respects :kind_filter (:video_objects only)" do
      on_exit_clear_table()

      seed_present_movie("Sample Movie")
      seed_present_video_object("Sample Video")

      assert :ok = Search.refresh_cache()

      results = Views.search("Sample", kind_filter: :video_objects)
      assert length(results) == 1
      assert hd(results).container_type == :video_object
    end

    test ":kind_filter :all is the default" do
      on_exit_clear_table()

      seed_present_movie("Sample Movie")
      seed_present_tv_series("Sample Show")

      assert :ok = Search.refresh_cache()

      results = Views.search("Sample")
      kinds = results |> Enum.map(& &1.container_type) |> Enum.sort()
      assert kinds == [:movie, :tv_series]
    end

    test "TV series, MovieSeries, VideoObject all indexed alongside Movies" do
      on_exit_clear_table()

      seed_present_movie("Sample Movie")
      seed_present_tv_series("Sample Show")
      seed_present_movie_series("Sample Saga")
      seed_present_video_object("Sample Video")

      assert :ok = Search.refresh_cache()

      results = Views.search("Sample")
      kinds = results |> Enum.map(& &1.container_type) |> Enum.sort()

      assert kinds == [:movie, :movie_series, :tv_series, :video_object]
    end
  end

  describe ":present_only filter" do
    test "present_only=false (default) includes all indexed entities" do
      on_exit_clear_table()

      seed_present_movie("Sample Movie")

      assert :ok = Search.refresh_cache()

      assert [%SearchItem{name: "Sample Movie"}] = Views.search("Sample")
    end

    test "present_only=false indexes both present and absent entities; :present_only=true filters absents out" do
      on_exit_clear_table()

      # Present movie — has WatchedFile + KnownFile(state: :present).
      seed_present_movie("Present Movie")

      # Absent movie — has a linked file recorded (so a PlayableItem
      # exists and the entity has something playable to surface) but
      # never marked present in the FilePresence/KnownFile registry.
      # The Search projection must index this entity so that the
      # :present_only filter does real work.
      absent = create_standalone_movie(%{name: "Absent Movie"})
      _file = create_linked_file(%{movie_id: absent.id})

      assert :ok = Search.refresh_cache()

      # Default (:present_only=false) — both surface.
      all_results = Views.search("Movie")
      all_names = Enum.map(all_results, & &1.name)
      assert "Present Movie" in all_names
      assert "Absent Movie" in all_names

      # :present_only=true filters the absent entity out.
      present_results = Views.search("Movie", present_only: true)
      assert Enum.all?(present_results, & &1.present?)

      present_names = Enum.map(present_results, & &1.name)
      assert "Present Movie" in present_names
      refute "Absent Movie" in present_names
    end

    test "present? on stored rows reflects real presence (true for present, false for absent)" do
      on_exit_clear_table()

      seed_present_movie("Present Movie")

      absent = create_standalone_movie(%{name: "Absent Movie"})
      _file = create_linked_file(%{movie_id: absent.id})

      assert :ok = Search.refresh_cache()

      all_results = Views.search("Movie")
      by_name = Map.new(all_results, &{&1.name, &1})

      assert %SearchItem{present?: true} = Map.fetch!(by_name, "Present Movie")
      assert %SearchItem{present?: false} = Map.fetch!(by_name, "Absent Movie")
    end
  end

  describe "SearchItem shape" do
    test "has typed fields (struct, not string-key map)" do
      on_exit_clear_table()

      seed_present_movie("Sample Movie", %{date_published: ~D[2010-06-01]})

      assert :ok = Search.refresh_cache()

      [item] = Views.search("Sample Movie")

      assert is_struct(item, SearchItem)
      assert is_binary(item.playable_item_id)
      assert is_binary(item.container_id)
      assert item.container_type == :movie
      assert item.name == "Sample Movie"
      assert is_float(item.score)
    end

    test "year derived from container.date_published when available" do
      on_exit_clear_table()

      seed_present_movie("Year Movie", %{date_published: ~D[2010-06-01]})

      assert :ok = Search.refresh_cache()

      [item] = Views.search("Year Movie")
      assert item.year == 2010
    end

    test "year is nil when container has no date_published" do
      on_exit_clear_table()

      seed_present_movie("No-Year Movie", %{date_published: nil})

      assert :ok = Search.refresh_cache()

      [item] = Views.search("No-Year Movie")
      assert item.year == nil
    end
  end

  describe "refresh via library:updates" do
    test "newly created Movie becomes searchable after :entities_changed broadcast" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      :ok = Search.refresh_cache()
      assert_receive {:library_view_updated, :search}, 1_000

      movie = seed_present_movie("Sample Movie")

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        Topics.library_updates(),
        {:entities_changed, %EntitiesChanged{entity_ids: [movie.id]}}
      )

      # Cache.Worker is NOT running in tests — drive the refresh manually,
      # synchronise via the derived topic.
      :ok = Search.refresh_cache()
      assert_receive {:library_view_updated, :search}, 1_000

      assert [%SearchItem{name: "Sample Movie"}] = Views.search("Sample Movie")
    end

    test "renamed entity is no longer matched by old name" do
      on_exit_clear_table()

      series = seed_present_tv_series("Old Name")
      :ok = Search.refresh_cache()

      assert [%SearchItem{name: "Old Name"}] = Views.search("Old Name")

      {:ok, _updated} = MediaCentarr.Library.update_tv_series(series, %{name: "New Name"})
      :ok = Search.refresh_cache()

      assert Views.search("Old Name") == []
      assert [%SearchItem{name: "New Name"}] = Views.search("New Name")
    end

    test "deleted entity disappears from results" do
      on_exit_clear_table()

      movie = seed_present_movie("Will Be Gone")
      :ok = Search.refresh_cache()

      assert [%SearchItem{name: "Will Be Gone"}] = Views.search("Will Be Gone")

      MediaCentarr.Repo.delete!(movie)
      :ok = Search.refresh_cache()

      assert Views.search("Will Be Gone") == []
    end
  end

  describe "broadcast contract" do
    test "emits {:library_view_updated, :search} on library:views after refresh" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      assert :ok = Search.refresh_cache()

      assert_receive {:library_view_updated, :search}, 1_000
    end

    test "broadcasts even when the projection is empty" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      assert :ok = Search.refresh_cache()

      assert_receive {:library_view_updated, :search}, 1_000
    end
  end

  describe "refresh via library:availability" do
    test "file becoming present flips present? on the indexed row" do
      on_exit_clear_table()

      # Movie with a file that hasn't been recorded present yet. The
      # entity is indexed from the start (search is presence-agnostic
      # at the source) but its `present?` is false until the file
      # flips to present.
      movie = create_standalone_movie(%{name: "Late Arrival"})
      file = create_linked_file(%{movie_id: movie.id})

      :ok = Search.refresh_cache()

      # Indexed without :present_only.
      assert [%SearchItem{name: "Late Arrival", present?: false}] =
               Views.search("Late Arrival")

      # Filtered out under :present_only=true.
      assert Views.search("Late Arrival", present_only: true) == []

      # File flips to present.
      record_present(file)

      :ok = Search.refresh_cache()

      # Now present? is true and :present_only=true surfaces it.
      assert [%SearchItem{name: "Late Arrival", present?: true}] =
               Views.search("Late Arrival", present_only: true)
    end
  end

  describe "Views.search/2 — ETS path vs DB fallback" do
    test "falls back to DB build when the ETS table is absent" do
      seed_present_movie("Cold Read")

      assert :undefined = :ets.whereis(@table)

      [item] = Views.search("Cold Read")
      assert item.name == "Cold Read"
      assert item.container_type == :movie
    end

    test "is idempotent — repeat refreshes replace the snapshot, no leak" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      assert :ok = Search.refresh_cache()
      assert length(Views.search("Movie")) == 1

      seed_present_movie("Movie B")
      assert :ok = Search.refresh_cache()
      assert length(Views.search("Movie")) == 2

      # Refreshing without DB changes preserves the snapshot.
      assert :ok = Search.refresh_cache()
      assert length(Views.search("Movie")) == 2
    end
  end

  describe "refresh cost is bounded — no N+1 over entity count" do
    # Phase 3 Task C follow-up M-1: representative-PlayableItem lookup
    # used to issue one query per indexed entity, scaling O(N) with
    # library size. The bulk lookup collapses this to O(1) per
    # container kind. The ceiling is generous (≤ 25 queries for 20
    # entities across kinds) — it's a regression guard, not a budget.
    @query_ceiling 25

    test "refresh_cache issues a bounded number of queries regardless of entity count" do
      on_exit_clear_table()

      # Seed 20 entities across all four kinds to exercise every bulk
      # lookup path. If lookups were N+1, query count would scale with
      # this count.
      Enum.each(1..5, fn i -> seed_present_movie("Movie #{i}") end)
      Enum.each(1..5, fn i -> seed_present_tv_series("Show #{i}") end)
      Enum.each(1..5, fn i -> seed_present_movie_series("Saga #{i}") end)
      Enum.each(1..5, fn i -> seed_present_video_object("Clip #{i}") end)

      {_result, queries} = count_queries(fn -> Search.refresh_cache() end)

      assert length(queries) <= @query_ceiling,
             "refresh_cache issued #{length(queries)} queries; ceiling is #{@query_ceiling}. " <>
               "Likely cause: representative PlayableItem lookup is back to N+1. " <>
               "Queries:\n" <>
               Enum.map_join(queries, "\n", fn {src, sql} -> "  #{src}: #{sql}" end)
    end

    # Telemetry-counter helper, inlined here per Phase 3 Task C
    # follow-up M-1. Task E owns the shared `no_db_on_render_test.exs`
    # helper; until then the inline form keeps the regression guard
    # local to the test that needs it.
    defp count_queries(fun) do
      ref = make_ref()
      parent = self()
      handler_id = {:search_refresh_query_count, ref}

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
  end

  describe "SearchItem struct" do
    test "enforces :playable_item_id, :container_type, :container_id, :name" do
      assert_raise ArgumentError, fn ->
        struct!(SearchItem, %{})
      end
    end

    test "permits nil values for the optional fields" do
      item = %SearchItem{
        playable_item_id: "pi-1",
        container_type: :movie,
        container_id: "c-1",
        name: "Name"
      }

      assert item.year == nil
      assert item.score == nil
      assert item.present? == nil
    end
  end
end
