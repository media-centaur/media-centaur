defmodule MediaCentarr.Library.Views.DetailTest do
  @moduledoc """
  Spec tests for the `Library.Views.Detail` ETS-backed projection (ADR-041,
  Library Schema v2 Phase 3 Task B).

  Tests through the public read API only — `Library.Views.detail/1`,
  `Library.Views.detail_by_container/2`, and `Detail.refresh_cache/0`.
  No `:sys.get_state`, no direct `:ets.lookup`, no `GenServer.call` on
  the worker. PubSub-synchronised assertions use the derived
  `library:views` topic to wait for partial-refresh completion.
  """
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Events.EntitiesChanged
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.{Detail, DetailItem}
  alias MediaCentarr.Topics

  @table :library_view_detail

  # Post-Phase-4 (library-presence-unification): `create_linked_file/1`
  # auto-stamps Library.FilePresence, so a linked file IS a present file.
  # Helper kept as a no-op so legacy seed code still reads clearly.
  defp record_present(_file), do: :ok

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
    file = create_linked_file(%{movie_id: movie.id})
    record_present(file)
    {movie, file}
  end

  defp seed_present_video_object(name) do
    vo = create_video_object(%{name: name})
    file = create_linked_file(%{video_object_id: vo.id})
    record_present(file)
    {vo, file}
  end

  defp seed_present_episode(series_name) do
    series = create_tv_series(%{name: series_name})
    season = create_season(%{tv_series_id: series.id, season_number: 1})

    episode =
      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        duration_seconds: 1800
      })

    # Explicitly create the PlayableItem for this episode and link the
    # file path through it — the `create_linked_file` factory shortcut
    # with `tv_series_id` creates a *synthetic* episode, not our
    # explicit one. Routing through `create_playable_item_for_episode`
    # is the public API for the leaf binding.
    playable_item = create_playable_item_for_episode(episode)

    file =
      create_linked_file(%{
        playable_item_id: playable_item.id,
        file_path: "/media/test/#{series_name}.S01E01.mkv"
      })

    record_present(file)
    {series, season, episode, file}
  end

  defp playable_item_for_movie(movie) do
    [item | _] = Library.list_playable_items_for(:movie, movie.id)
    item
  end

  defp playable_item_for_episode(episode) do
    [item | _] = Library.list_playable_items_for(:episode, episode.id)
    item
  end

  defp playable_item_for_video_object(vo) do
    [item | _] = Library.list_playable_items_for(:video_object, vo.id)
    item
  end

  describe "Cache behaviour — relevant?/1" do
    test "accepts library entity-changed events" do
      assert Detail.relevant?({:entities_changed, %{entity_ids: ["x"]}})
    end

    test "accepts availability-changed events" do
      assert Detail.relevant?({:availability_changed, "/media/test", :available})
      assert Detail.relevant?({:availability_changed, "/media/test", :unavailable})
    end

    test "rejects unrelated messages" do
      refute Detail.relevant?(:something_else)
      refute Detail.relevant?({:other, "payload"})
      refute Detail.relevant?({:watch_event_created, %{}})
    end
  end

  describe "cold start — refresh_cache/0 populates the ETS table" do
    test "returns nil for unknown playable_item_id" do
      on_exit_clear_table()

      assert :ok = Detail.refresh_cache()
      assert Views.detail(Ecto.UUID.generate()) == nil
    end

    test "returns DetailItem for a standalone Movie with its PlayableItem" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Movie A", %{date_published: ~D[2010-01-01]})
      pi = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      assert %DetailItem{} = item = Views.detail(pi.id)
      assert item.playable_item_id == pi.id
      assert item.container_type == :movie
      assert item.container_id == movie.id
      assert item.container_name == "Movie A"
      assert item.container_year == 2010
      assert item.present? == true
    end

    test "DetailItem includes preloaded cast/crew for a Movie" do
      on_exit_clear_table()

      {movie, _file} =
        seed_present_movie("Cast Movie", %{
          cast: [%{name: "Actor A", character: "Role A", order: 0, tmdb_person_id: 1}],
          crew: [%{name: "Director B", job: "Director", department: "Directing", tmdb_person_id: 2}]
        })

      pi = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(pi.id)
      assert [%{name: "Actor A"}] = item.cast
      assert [%{name: "Director B", job: "Director"}] = item.crew
    end

    test "DetailItem includes preloaded extras for a Movie" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Movie With Extras")
      _extra = create_extra(%{movie_id: movie.id, name: "Behind the Scenes", position: 1})

      pi = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(pi.id)
      assert [%{name: "Behind the Scenes"}] = item.extras
    end

    test "DetailItem includes preloaded external_ids for a Movie" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("ExtIds Movie", %{tmdb_id: "12345", imdb_id: "tt0001"})
      pi = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(pi.id)
      sources = item.external_ids |> Enum.map(& &1.source) |> Enum.sort()
      assert sources == ["imdb", "tmdb"]
      assert item.imdb_id == "tt0001"
    end

    test "returns DetailItem for an Episode with TVSeries container metadata" do
      on_exit_clear_table()

      {series, _season, episode, _file} = seed_present_episode("Sample Series")
      pi = playable_item_for_episode(episode)

      assert :ok = Detail.refresh_cache()

      assert %DetailItem{} = item = Views.detail(pi.id)
      assert item.container_type == :episode
      assert item.container_id == episode.id
      # Episode-level name + the parent TVSeries-level container metadata.
      assert item.name == "Pilot"
      assert item.parent_container_type == :tv_series
      assert item.parent_container_id == series.id
      assert item.parent_container_name == "Sample Series"
    end

    test "returns DetailItem for a VideoObject's PlayableItem" do
      on_exit_clear_table()

      {vo, _file} = seed_present_video_object("Concert A")
      pi = playable_item_for_video_object(vo)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(pi.id)
      assert item.container_type == :video_object
      assert item.container_id == vo.id
      assert item.container_name == "Concert A"
    end

    test "DetailItem.present? reflects file presence" do
      on_exit_clear_table()

      # Post-Phase-4 (library-presence-unification): present? is true
      # iff a WatchedFile exists. Drop just the WatchedFile here to
      # isolate the present?-flip assertion — the full cleanup path
      # (ADR-046) would also remove the entity, defeating the test.
      movie = create_standalone_movie(%{name: "Disappearing Movie"})
      file = create_linked_file(%{movie_id: movie.id})
      pi = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()
      assert %DetailItem{present?: true} = Views.detail(pi.id)

      MediaCentarr.Repo.delete!(file)

      assert :ok = Detail.refresh_cache()
      assert %DetailItem{present?: false} = Views.detail(pi.id)
    end

    test "DetailItem.present? is false for a PlayableItem with no WatchedFile" do
      on_exit_clear_table()

      # Movie with a PlayableItem but no WatchedFile at all.
      movie = create_standalone_movie(%{name: "Fileless Movie"})
      {:ok, pi} = Library.find_or_create_playable_item(:movie, movie.id, 1)

      assert :ok = Detail.refresh_cache()
      item = Views.detail(pi.id)
      assert item.present? == false
    end
  end

  describe "refresh via library:updates" do
    test "metadata edit on a TVSeries reflects in next read for its episode PlayableItem" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      {series, _season, episode, _file} = seed_present_episode("Old Title")
      pi = playable_item_for_episode(episode)

      assert :ok = Detail.refresh_cache()
      assert %DetailItem{parent_container_name: "Old Title"} = Views.detail(pi.id)

      {:ok, _updated} = Library.update_tv_series(series, %{name: "New Title"})

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        Topics.library_updates(),
        {:entities_changed, %EntitiesChanged{entity_ids: [series.id]}}
      )

      :ok = Detail.refresh_cache()
      assert_receive {:library_view_updated, :detail, broadcasted_id}, 1_000
      assert broadcasted_id == pi.id

      assert %DetailItem{parent_container_name: "New Title"} = Views.detail(pi.id)
    end

    test "deleted Movie's DetailItem is removed from the table" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Will Be Gone")
      pi = playable_item_for_movie(movie)

      :ok = Detail.refresh_cache()
      assert %DetailItem{} = Views.detail(pi.id)

      MediaCentarr.Repo.delete!(movie)

      :ok = Detail.refresh_cache()
      assert Views.detail(pi.id) == nil
    end
  end

  describe "refresh via library:availability" do
    test "file becoming present updates present? to true" do
      on_exit_clear_table()

      # Post-Phase-4 (library-presence-unification): "becoming present"
      # means the WatchedFile getting stamped. Start with a PlayableItem
      # but no WatchedFile; stamp it and watch present? flip.
      movie = create_standalone_movie(%{name: "Late Arrival"})
      {:ok, pi} = Library.find_or_create_playable_item(:movie, movie.id, 1)

      assert :ok = Detail.refresh_cache()
      assert %DetailItem{present?: false} = Views.detail(pi.id)

      _file = create_linked_file(%{movie_id: movie.id})

      :ok = Detail.refresh_cache()
      assert %DetailItem{present?: true} = Views.detail(pi.id)
    end
  end

  describe "broadcast contract" do
    test "emits {:library_view_updated, :detail, playable_item_id} (3-tuple, NOT 2-tuple)" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Broadcast Movie")
      pi = playable_item_for_movie(movie)

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      assert :ok = Detail.refresh_cache()

      # Cold start broadcasts one message per row in the table.
      assert_receive {:library_view_updated, :detail, broadcasted_id}, 1_000
      assert broadcasted_id == pi.id

      # Must NOT be the 2-tuple shape used by Browse.
      refute_received {:library_view_updated, :detail}
    end

    test "broadcasts one message per affected row, not a firehose 2-tuple" do
      on_exit_clear_table()

      {movie_a, _file_a} = seed_present_movie("Movie Alpha")
      {movie_b, _file_b} = seed_present_movie("Movie Bravo")
      pi_a = playable_item_for_movie(movie_a)
      pi_b = playable_item_for_movie(movie_b)

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      assert :ok = Detail.refresh_cache()

      received_ids =
        for _ <- 1..2 do
          assert_receive {:library_view_updated, :detail, id}, 1_000
          id
        end

      assert Enum.sort(received_ids) == Enum.sort([pi_a.id, pi_b.id])
    end
  end

  describe "detail_by_container/2" do
    test "resolves a Movie container UUID to its sole PlayableItem" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Resolve Me")
      pi = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      assert %DetailItem{playable_item_id: id} = Views.detail_by_container(:movie, movie.id)
      assert id == pi.id
    end

    test "resolves a VideoObject container UUID to its PlayableItem" do
      on_exit_clear_table()

      {vo, _file} = seed_present_video_object("VO Resolve")
      pi = playable_item_for_video_object(vo)

      assert :ok = Detail.refresh_cache()

      assert %DetailItem{playable_item_id: id} = Views.detail_by_container(:video_object, vo.id)
      assert id == pi.id
    end

    test "returns nil for an unknown container UUID" do
      on_exit_clear_table()

      assert :ok = Detail.refresh_cache()
      assert Views.detail_by_container(:movie, Ecto.UUID.generate()) == nil
    end

    test "returns nil for :tv_series — TVSeries has no canonical PlayableItem at container level" do
      on_exit_clear_table()

      {series, _season, _episode, _file} = seed_present_episode("TV Resolve")

      assert :ok = Detail.refresh_cache()

      assert Views.detail_by_container(:tv_series, series.id) == nil
    end

    test "returns the position=1 PlayableItem when multiple cuts exist for a Movie" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Multi-Cut Movie")
      pi_one = playable_item_for_movie(movie)
      # Seed a second cut at position 2.
      {:ok, pi_two} = Library.find_or_create_playable_item(:movie, movie.id, 2)

      assert :ok = Detail.refresh_cache()

      result = Views.detail_by_container(:movie, movie.id)
      assert result.playable_item_id == pi_one.id
      refute result.playable_item_id == pi_two.id
    end
  end

  describe "DetailItem struct" do
    test "enforces :playable_item_id, :container_type, :container_id, :name" do
      assert_raise ArgumentError, fn ->
        struct!(DetailItem, %{})
      end
    end

    test "is a typed struct, not a string-keyed map" do
      item = %DetailItem{
        playable_item_id: "pi-1",
        container_type: :movie,
        container_id: "c-1",
        name: "Name"
      }

      assert is_struct(item, DetailItem)
      assert item.cast == nil
      assert item.extras == nil
      assert item.external_ids == nil
      assert item.present? == nil
    end
  end

  describe "Views.detail/1 — ETS path vs DB fallback" do
    test "falls back to DB query when the ETS table is absent" do
      {movie, _file} = seed_present_movie("Cold Read")
      pi = playable_item_for_movie(movie)

      assert :undefined = :ets.whereis(@table)

      item = Views.detail(pi.id)
      assert item.container_name == "Cold Read"
      assert item.container_type == :movie
    end

    test "is idempotent — repeat refreshes replace per-row entries, no leak" do
      on_exit_clear_table()

      {movie_a, _file_a} = seed_present_movie("Idempotent A")
      pi_a = playable_item_for_movie(movie_a)
      :ok = Detail.refresh_cache()
      assert %DetailItem{} = Views.detail(pi_a.id)

      {movie_b, _file_b} = seed_present_movie("Idempotent B")
      pi_b = playable_item_for_movie(movie_b)
      :ok = Detail.refresh_cache()

      assert %DetailItem{} = Views.detail(pi_a.id)
      assert %DetailItem{} = Views.detail(pi_b.id)

      # Repeated refresh without DB changes preserves the rows.
      :ok = Detail.refresh_cache()
      assert %DetailItem{} = Views.detail(pi_a.id)
      assert %DetailItem{} = Views.detail(pi_b.id)
    end
  end
end
