defmodule MediaCentarr.Library.Views.BrowseTest do
  @moduledoc """
  Spec tests for the `Library.Views.Browse` ETS-backed projection (ADR-041,
  Phase 3 Task A).

  Tests through the public read API only — `Library.Views.browse/1` and
  `Browse.refresh_cache/0`. No `:sys.get_state`, no direct `:ets.lookup`,
  no `GenServer.call` on the worker. PubSub-synchronised assertions use
  the derived `library:views` topic to wait for refresh completion.
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library.Events.EntitiesChanged
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.{Browse, BrowseItem}
  alias MediaCentarr.Topics
  alias MediaCentarr.Watcher.FilePresence

  @table :library_view_browse

  defp record_present(file), do: FilePresence.record_file(file.file_path, file.watch_dir)

  # ETS table is global; tests that exercise the cached path must clean
  # up so later tests fall back to a clean slate.
  defp on_exit_clear_table do
    on_exit(fn ->
      case :ets.whereis(@table) do
        :undefined -> :ok
        _ref -> :ets.delete(@table)
      end
    end)
  end

  # Seeds a standalone movie with a present file so the entity passes
  # presentable-filter queries. The factory hooks PlayableItem +
  # WatchedFile automatically when given :movie_id.
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

  # A movie series only appears in the browse projection when it has at
  # least two child movies (singletons get hoisted to standalone movies
  # via `PresentableQueries.singleton_collection_movies/0`). Seed two
  # present children so the multi-child shape qualifies.
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
      assert Browse.relevant?({:entities_changed, %{entity_ids: ["x"]}})
    end

    test "accepts availability-changed events (drive mount / unmount)" do
      assert Browse.relevant?({:availability_changed, "/media/test", :available})
      assert Browse.relevant?({:availability_changed, "/media/test", :unavailable})
    end

    test "rejects unrelated messages" do
      refute Browse.relevant?(:something_else)
      refute Browse.relevant?({:watch_event_created, %{}})
      refute Browse.relevant?({:entity_progress_updated, %{}})
      refute Browse.relevant?({:other, "payload"})
    end
  end

  describe "cold start — refresh_cache/0 populates the ETS table" do
    test "returns empty when library is empty" do
      on_exit_clear_table()

      assert :ok = Browse.refresh_cache()
      assert Views.browse() == []
    end

    test "returns standalone movies sorted by name (case-insensitive)" do
      on_exit_clear_table()

      seed_present_movie("Movie B")
      seed_present_movie("Movie A")
      seed_present_movie("movie c")

      assert :ok = Browse.refresh_cache()

      items = Views.browse()
      assert length(items) == 3
      assert Enum.all?(items, &is_struct(&1, BrowseItem))

      names = Enum.map(items, & &1.name)
      assert names == ["Movie A", "Movie B", "movie c"]
    end

    test "returns TV series, movie series, and video objects alongside movies" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      seed_present_tv_series("Series A")
      seed_present_movie_series("MSeries A")
      seed_present_video_object("VideoObject A")

      assert :ok = Browse.refresh_cache()

      items = Views.browse()
      kinds = Enum.sort(Enum.map(items, & &1.kind))

      assert kinds == [:movie, :movie_series, :tv_series, :video_object]
    end

    test "assigns rank in display order, starting at 0" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      seed_present_movie("Movie B")
      seed_present_movie("Movie C")

      assert :ok = Browse.refresh_cache()

      ranks = Enum.map(Views.browse(), & &1.rank)
      assert ranks == [0, 1, 2]
    end

    test "year is derived from container.date_published" do
      on_exit_clear_table()

      seed_present_movie("Year Movie", %{date_published: ~D[2010-06-01]})
      seed_present_movie("No-Year Movie", %{date_published: nil})

      assert :ok = Browse.refresh_cache()

      items = Views.browse()
      by_name = Map.new(items, &{&1.name, &1})

      assert by_name["Year Movie"].year == 2010
      assert by_name["No-Year Movie"].year == nil
    end

    test "poster_url is populated when entity has a poster image" do
      on_exit_clear_table()

      movie = seed_present_movie("Poster Movie")

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      seed_present_movie("No Poster Movie")

      assert :ok = Browse.refresh_cache()

      items = Views.browse()
      by_name = Map.new(items, &{&1.name, &1})

      assert by_name["Poster Movie"].poster_url == "/media-images/#{movie.id}/poster.jpg"
      assert by_name["No Poster Movie"].poster_url == nil
    end

    test "present? is true for entities with a present WatchedFile" do
      on_exit_clear_table()

      seed_present_movie("Present Movie")
      assert :ok = Browse.refresh_cache()

      [item] = Views.browse()
      assert item.present? == true
    end
  end

  describe "Views.browse/1 — filters" do
    test "respects :kind filter (movies only)" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      seed_present_tv_series("Series A")
      seed_present_video_object("VO A")

      assert :ok = Browse.refresh_cache()

      movies = Views.browse(kind: :movie)
      assert length(movies) == 1
      assert hd(movies).kind == :movie
      assert hd(movies).name == "Movie A"
    end

    test "respects :kind filter (tv_series only)" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      seed_present_tv_series("Series A")
      seed_present_tv_series("Series B")

      assert :ok = Browse.refresh_cache()

      tv = Views.browse(kind: :tv_series)
      assert length(tv) == 2
      assert Enum.all?(tv, &(&1.kind == :tv_series))
    end

    test ":present_only excludes entities with no present WatchedFile" do
      on_exit_clear_table()

      # A standalone movie WITH a present file.
      seed_present_movie("Present Movie")

      # A standalone movie WITHOUT a present file. The browse query uses
      # PresentableQueries which already filters to entities with present
      # files, so an entity without a file simply won't appear in the
      # projection at all — :present_only is a stricter view of the same
      # data, primarily useful when the underlying query relaxes later.
      _absent = create_standalone_movie(%{name: "Absent Movie"})

      assert :ok = Browse.refresh_cache()

      present = Views.browse(present_only: true)
      assert Enum.all?(present, & &1.present?)
      names = Enum.map(present, & &1.name)
      assert "Present Movie" in names
      refute "Absent Movie" in names
    end
  end

  describe "refresh via library:updates" do
    test "newly created entity appears in next read after :entities_changed broadcast" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      # Prime the cache so we start from a known state.
      :ok = Browse.refresh_cache()
      assert_receive {:library_view_updated, :browse}, 1_000

      movie = seed_present_movie("Sample Movie")

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        Topics.library_updates(),
        {:entities_changed, %EntitiesChanged{entity_ids: [movie.id]}}
      )

      # The Cache.Worker is NOT running in tests (cache_children(:test) = [])
      # — drive the refresh manually then synchronise via the derived topic.
      :ok = Browse.refresh_cache()
      assert_receive {:library_view_updated, :browse}, 1_000

      assert [%BrowseItem{name: "Sample Movie"}] = Views.browse()
    end

    test "deleted entity disappears in next read after refresh" do
      on_exit_clear_table()

      movie = seed_present_movie("Will Be Gone")
      :ok = Browse.refresh_cache()
      assert [%BrowseItem{name: "Will Be Gone"}] = Views.browse()

      # Library has no public delete_movie/1 today (cascade deletes flow
      # from FileEventHandler when files disappear). For the projection
      # contract test it's the *absence* in the next refresh that
      # matters, not the deletion path — Repo.delete! is the most direct
      # way to simulate the post-delete DB state. Tests may touch Repo
      # directly; the production rule is "no Repo on the LiveView render
      # path", not "never in tests".
      MediaCentarr.Repo.delete!(movie)

      :ok = Browse.refresh_cache()
      assert Views.browse() == []
    end

    test "renamed entity's BrowseItem.name reflects the update after refresh" do
      on_exit_clear_table()

      # Library exposes `update_tv_series/2` but not `update_movie/2`
      # (see Library context API). Use a TVSeries here to stay on the
      # public context API for the rename contract.
      series = seed_present_tv_series("Old Name")
      :ok = Browse.refresh_cache()

      {:ok, _updated} = MediaCentarr.Library.update_tv_series(series, %{name: "New Name"})

      :ok = Browse.refresh_cache()

      [item] = Views.browse()
      assert item.name == "New Name"
    end
  end

  describe "refresh via library:availability" do
    # The browse query is presence-aware: PresentableQueries.standalone_movies/0
    # already filters by `kf.state == :present`. A file flipping from
    # present to absent removes the entity from the projection's next
    # refresh; flipping back surfaces it again. The Cache.Worker drives
    # refreshes on availability_changed broadcasts in production.
    test "file becoming present surfaces the entity in next refresh" do
      on_exit_clear_table()

      # A movie whose file is NOT yet recorded as present.
      movie = create_standalone_movie(%{name: "Late Arrival"})
      file = create_linked_file(%{movie_id: movie.id})

      :ok = Browse.refresh_cache()
      assert Views.browse() == []

      # File flips to present.
      record_present(file)

      :ok = Browse.refresh_cache()
      assert [%BrowseItem{name: "Late Arrival"}] = Views.browse()
    end
  end

  describe "broadcast contract" do
    test "emits {:library_view_updated, :browse} on library:views after refresh" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      assert :ok = Browse.refresh_cache()

      assert_receive {:library_view_updated, :browse}, 1_000
    end

    test "broadcasts even when the projection is empty" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      assert :ok = Browse.refresh_cache()

      assert_receive {:library_view_updated, :browse}, 1_000
    end
  end

  describe "Views.browse/1 — ETS path vs DB fallback" do
    test "falls back to DB query when the ETS table is absent" do
      seed_present_movie("Cold Read")

      assert :undefined = :ets.whereis(@table)

      [item] = Views.browse()
      assert item.name == "Cold Read"
      assert item.kind == :movie
    end

    test "is idempotent — repeat refreshes replace the snapshot, no leak" do
      on_exit_clear_table()

      seed_present_movie("Movie A")
      assert :ok = Browse.refresh_cache()
      assert length(Views.browse()) == 1

      seed_present_movie("Movie B")
      assert :ok = Browse.refresh_cache()
      assert length(Views.browse()) == 2

      # Refreshing without DB changes preserves the snapshot.
      assert :ok = Browse.refresh_cache()
      assert length(Views.browse()) == 2
    end
  end

  describe "BrowseItem struct" do
    test "enforces :id, :kind, and :name" do
      assert_raise ArgumentError, fn ->
        struct!(BrowseItem, %{})
      end
    end

    test "is a typed struct, not a string-keyed map" do
      item = %BrowseItem{id: "id-1", kind: :movie, name: "Name"}

      assert is_struct(item, BrowseItem)
      assert item.year == nil
      assert item.poster_url == nil
      assert item.present? == nil
      assert item.rank == nil
    end
  end
end
