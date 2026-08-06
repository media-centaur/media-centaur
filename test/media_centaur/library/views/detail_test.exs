defmodule MediaCentaur.Library.Views.DetailTest do
  @moduledoc """
  Spec tests for the `Library.Views.Detail` ETS-backed projection (ADR-041,
  Library Schema v2 Phase 3 Task B).

  Tests through the public read API only — `Library.Views.detail/1`,
  `Library.Views.detail_by_container/2`, and `Detail.refresh_cache/0`.
  No `:sys.get_state`, no direct `:ets.lookup`, no `GenServer.call` on
  the worker. PubSub-synchronised assertions use the derived
  `library:views` topic to wait for partial-refresh completion.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Events.EntitiesChanged
  alias MediaCentaur.Library.Views
  alias MediaCentaur.Library.Views.{Detail, DetailItem}
  alias MediaCentaur.Topics

  @table :library_view_detail
  @shared_table :library_view_detail_shared

  # Post-Phase-4 (library-presence-unification): `create_linked_file/1`
  # auto-stamps Library.FilePresence, so a linked file IS a present file.
  # Helper kept as a no-op so legacy seed code still reads clearly.
  defp record_present(_file), do: :ok

  defp on_exit_clear_table do
    on_exit(fn ->
      for table <- [@table, @shared_table] do
        case :ets.whereis(table) do
          :undefined -> :ok
          _ref -> :ets.delete(table)
        end
      end
    end)
  end

  # Two billed cast members — enough to prove the shared payload survives
  # the split without bloating the fixture.
  defp sample_cast do
    [
      %{name: "Actor One", character: "Lead", order: 0, tmdb_person_id: 1},
      %{name: "Actor Two", character: "Support", order: 1, tmdb_person_id: 2}
    ]
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

  defp seed_present_episode(series_name, series_overrides \\ %{}) do
    series = create_tv_series(Map.merge(%{name: series_name}, series_overrides))
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
    [item | _] = Library.PlayableItems.list_for(:movie, movie.id)
    item
  end

  defp playable_item_for_episode(episode) do
    [item | _] = Library.PlayableItems.list_for(:episode, episode.id)
    item
  end

  defp playable_item_for_video_object(vo) do
    [item | _] = Library.PlayableItems.list_for(:video_object, vo.id)
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
      playable_item = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      assert %DetailItem{} = item = Views.detail(playable_item.id)
      assert item.playable_item_id == playable_item.id
      assert item.container_type == :movie
      assert item.container_id == movie.id
      assert item.container_name == "Movie A"
      assert item.container_date_published == ~D[2010-01-01]
      assert item.present? == true
    end

    test "DetailItem includes preloaded cast/crew for a Movie" do
      on_exit_clear_table()

      {movie, _file} =
        seed_present_movie("Cast Movie", %{
          cast: [%{name: "Actor A", character: "Role A", order: 0, tmdb_person_id: 1}],
          crew: [%{name: "Director B", job: "Director", department: "Directing", tmdb_person_id: 2}]
        })

      playable_item = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(playable_item.id)
      assert [%{name: "Actor A"}] = item.cast
      assert [%{name: "Director B", job: "Director"}] = item.crew
    end

    test "DetailItem includes preloaded extras for a Movie" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Movie With Extras")
      _extra = create_extra(%{movie_id: movie.id, name: "Behind the Scenes", position: 1})

      playable_item = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(playable_item.id)
      assert [%{name: "Behind the Scenes"}] = item.extras
    end

    test "DetailItem includes preloaded external_ids for a Movie" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("ExtIds Movie", %{tmdb_id: "12345", imdb_id: "tt0001"})
      playable_item = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(playable_item.id)
      sources = item.external_ids |> Enum.map(& &1.source) |> Enum.sort()
      assert sources == ["imdb", "tmdb"]
      assert item.imdb_id == "tt0001"
    end

    test "returns DetailItem for an Episode with TVSeries container metadata" do
      on_exit_clear_table()

      {series, _season, episode, _file} = seed_present_episode("Sample Series")
      playable_item = playable_item_for_episode(episode)

      assert :ok = Detail.refresh_cache()

      assert %DetailItem{} = item = Views.detail(playable_item.id)
      assert item.container_type == :episode
      assert item.container_id == episode.id
      # Episode-level name + the parent TVSeries-level container metadata.
      assert item.name == "Pilot"
      assert item.parent_container_type == :tv_series
      assert item.parent_container_id == series.id
      assert item.parent_container_name == "Sample Series"
    end

    test "carries the episode's own air date onto the season's episode row" do
      on_exit_clear_table()

      series = create_tv_series(%{name: "Aired Series"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          date_published: ~D[2008-01-20]
        })

      playable_item = create_playable_item_for_episode(episode)

      create_linked_file(%{
        playable_item_id: playable_item.id,
        file_path: "/media/test/Aired Series.S01E01.mkv"
      })

      assert :ok = Detail.refresh_cache()

      item = Views.detail(playable_item.id)

      assert [season_row] = item.seasons
      assert [episode_row] = season_row.episodes
      assert episode_row.date_published == ~D[2008-01-20]
    end

    test "carries the TVSeries first-air date as container_date_published" do
      on_exit_clear_table()

      {_series, _season, episode, _file} =
        seed_present_episode("Dated Series", %{date_published: ~D[2019-04-08]})

      playable_item = playable_item_for_episode(episode)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(playable_item.id)
      assert item.container_date_published == ~D[2019-04-08]
    end

    test "returns DetailItem for a VideoObject's PlayableItem" do
      on_exit_clear_table()

      {vo, _file} = seed_present_video_object("Concert A")
      playable_item = playable_item_for_video_object(vo)

      assert :ok = Detail.refresh_cache()

      item = Views.detail(playable_item.id)
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
      playable_item = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()
      assert %DetailItem{present?: true} = Views.detail(playable_item.id)

      MediaCentaur.Repo.delete!(file)

      assert :ok = Detail.refresh_cache()
      assert %DetailItem{present?: false} = Views.detail(playable_item.id)
    end

    test "DetailItem.present? is false for a PlayableItem with no WatchedFile" do
      on_exit_clear_table()

      # Movie with a PlayableItem but no WatchedFile at all.
      movie = create_standalone_movie(%{name: "Fileless Movie"})
      {:ok, playable_item} = Library.PlayableItems.find_or_create(:movie, movie.id, 1)

      assert :ok = Detail.refresh_cache()
      item = Views.detail(playable_item.id)
      assert item.present? == false
    end
  end

  describe "refresh via library:updates" do
    test "metadata edit on a TVSeries reflects in next read for its episode PlayableItem" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.library_views())

      {series, _season, episode, _file} = seed_present_episode("Old Title")
      playable_item = playable_item_for_episode(episode)

      assert :ok = Detail.refresh_cache()
      assert %DetailItem{parent_container_name: "Old Title"} = Views.detail(playable_item.id)

      {:ok, _updated} = Library.Containers.update(series, %{name: "New Title"})

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.library_updates(),
        {:entities_changed, %EntitiesChanged{entity_ids: [series.id]}}
      )

      :ok = Detail.refresh_cache()
      # A full rebuild announces the whole table, not each row.
      assert_receive {:library_view_updated, :detail, :all}, 1_000

      assert %DetailItem{parent_container_name: "New Title"} = Views.detail(playable_item.id)
    end

    test "deleted Movie's DetailItem is removed from the table" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Will Be Gone")
      playable_item = playable_item_for_movie(movie)

      :ok = Detail.refresh_cache()
      assert %DetailItem{} = Views.detail(playable_item.id)

      MediaCentaur.Repo.delete!(movie)

      :ok = Detail.refresh_cache()
      assert Views.detail(playable_item.id) == nil
    end
  end

  describe "refresh via library:availability" do
    test "file becoming present updates present? to true" do
      on_exit_clear_table()

      # Post-Phase-4 (library-presence-unification): "becoming present"
      # means the WatchedFile getting stamped. Start with a PlayableItem
      # but no WatchedFile; stamp it and watch present? flip.
      movie = create_standalone_movie(%{name: "Late Arrival"})
      {:ok, playable_item} = Library.PlayableItems.find_or_create(:movie, movie.id, 1)

      assert :ok = Detail.refresh_cache()
      assert %DetailItem{present?: false} = Views.detail(playable_item.id)

      _file = create_linked_file(%{movie_id: movie.id})

      :ok = Detail.refresh_cache()
      assert %DetailItem{present?: true} = Views.detail(playable_item.id)
    end
  end

  describe "broadcast contract" do
    test "a full rebuild emits exactly one :all message, not one per row" do
      on_exit_clear_table()

      # Three rows. A per-row fan-out on full rebuild made every open
      # detail modal re-read (and re-render) once per row in the whole
      # library — 765 reads on a real library to converge on the row it
      # already had. The whole-table refresh is a single event.
      {movie_a, _} = seed_present_movie("Movie Alpha")
      {movie_b, _} = seed_present_movie("Movie Bravo")
      {movie_c, _} = seed_present_movie("Movie Charlie")
      for m <- [movie_a, movie_b, movie_c], do: playable_item_for_movie(m)

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.library_views())

      assert :ok = Detail.refresh_cache()

      assert_receive {:library_view_updated, :detail, :all}, 1_000
      refute_received {:library_view_updated, :detail, _other}

      # Must NOT be the 2-tuple shape used by Browse.
      refute_received {:library_view_updated, :detail}
    end

    test "a partial rebuild still emits the per-row 3-tuple" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Targeted Movie")
      playable_item = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.library_views())

      :ok = Detail.handle_message({:entities_changed, %EntitiesChanged{entity_ids: [movie.id]}})

      assert_receive {:library_view_updated, :detail, broadcasted_id}, 1_000
      assert broadcasted_id == playable_item.id
    end
  end

  describe "shared entity payload is stored once per entity" do
    test "sibling episode rows read back identical cast and seasons" do
      on_exit_clear_table()

      series = create_tv_series(%{name: "Shared Payload Show", cast: sample_cast()})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      pis =
        for n <- 1..3 do
          episode =
            create_episode(%{season_id: season.id, episode_number: n, name: "Episode #{n}"})

          playable_item = create_playable_item_for_episode(episode)
          create_linked_file(%{playable_item_id: playable_item.id, file_path: "/media/s01e0#{n}.mkv"})
          playable_item
        end

      assert :ok = Detail.refresh_cache()

      [first | rest] = Enum.map(pis, &Views.detail(&1.id))

      assert length(first.cast) == 2
      assert first.cast == Enum.at(rest, 0).cast
      assert first.seasons == Enum.at(rest, 0).seasons
      assert first.cast == Enum.at(rest, 1).cast
      assert first.seasons == Enum.at(rest, 1).seasons
    end

    test "a row still reads when the shared table is gone" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Orphaned Shared Movie")
      playable_item = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      # The two tables have independent lifetimes: a hot code reload in dev
      # kills the owning process and takes its tables with it, and they can
      # come back one at a time. A read that raises here would 500 the detail
      # modal instead of degrading to a metadata-less row.
      :ets.delete(@shared_table)

      assert %DetailItem{name: "Orphaned Shared Movie"} = Views.detail(playable_item.id)
    end

    test "the shared table holds one entry per entity, not one per row" do
      on_exit_clear_table()

      series = create_tv_series(%{name: "One Entry Show", cast: sample_cast()})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      for n <- 1..4 do
        episode = create_episode(%{season_id: season.id, episode_number: n, name: "Ep #{n}"})
        playable_item = create_playable_item_for_episode(episode)
        create_linked_file(%{playable_item_id: playable_item.id, file_path: "/media/one/s01e0#{n}.mkv"})
      end

      assert :ok = Detail.refresh_cache()

      # Four rows, one entity. Storing the cast + season tree per row is
      # what made the projection 219 MB for a 765-row library — ETS
      # deep-copies each row, so functional sharing does not survive the
      # `:ets.insert` boundary.
      assert :ets.info(:library_view_detail, :size) == 4
      assert :ets.info(:library_view_detail_shared, :size) == 1
    end
  end

  describe "collection hoist — presented_as" do
    test "a sole-possessed collection movie presents as a faithful movie with a collection reference" do
      ms = create_movie_series(%{name: "Singleton Collection", genres: ["Adventure"]})

      child =
        create_movie(%{
          movie_series_id: ms.id,
          name: "Sole Child",
          genres: ["Action"],
          position: 0
        })

      record_present(create_linked_file(%{movie_id: child.id}))

      entity = DetailItem.to_entity_map(Views.detail_by_container(:movie, child.id))

      # Presents as the movie itself — not the collection container.
      assert entity.type == :movie
      assert entity.id == child.id
      assert entity.name == "Sole Child"
      # Facets are the movie's own, not the collection's.
      assert entity.genres == ["Action"]
      # The relationship survives as a reference (for the badge).
      assert entity.collection == %{id: ms.id, name: "Singleton Collection"}
    end

    test "a multi-possessed collection still presents as the collection" do
      ms = create_movie_series(%{name: "Trilogy", genres: ["Adventure"]})
      part1 = create_movie(%{movie_series_id: ms.id, name: "Part 1", position: 0})
      part2 = create_movie(%{movie_series_id: ms.id, name: "Part 2", position: 1})
      record_present(create_linked_file(%{movie_id: part1.id}))
      record_present(create_linked_file(%{movie_id: part2.id}))

      entity = DetailItem.to_entity_map(Views.detail_by_container(:movie_series, ms.id))

      assert entity.type == :movie_series
      assert entity.id == ms.id
      assert entity.name == "Trilogy"
    end
  end

  describe "detail_by_container/2" do
    test "resolves a Movie container UUID to its sole PlayableItem" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Resolve Me")
      playable_item = playable_item_for_movie(movie)

      assert :ok = Detail.refresh_cache()

      assert %DetailItem{playable_item_id: id} = Views.detail_by_container(:movie, movie.id)
      assert id == playable_item.id
    end

    test "resolves a VideoObject container UUID to its PlayableItem" do
      on_exit_clear_table()

      {vo, _file} = seed_present_video_object("VO Resolve")
      playable_item = playable_item_for_video_object(vo)

      assert :ok = Detail.refresh_cache()

      assert %DetailItem{playable_item_id: id} = Views.detail_by_container(:video_object, vo.id)
      assert id == playable_item.id
    end

    test "returns nil for an unknown container UUID" do
      on_exit_clear_table()

      assert :ok = Detail.refresh_cache()
      assert Views.detail_by_container(:movie, Ecto.UUID.generate()) == nil
    end

    test "returns canonical episode's DetailItem for :tv_series (Phase 3.2)" do
      on_exit_clear_table()

      {series, _season, _episode, _file} = seed_present_episode("TV Resolve")

      assert :ok = Detail.refresh_cache()

      item = Views.detail_by_container(:tv_series, series.id)
      refute item == nil
      assert item.container_type == :episode
      assert item.parent_container_id == series.id
      assert is_list(item.seasons)
    end

    test "returns the position=1 PlayableItem when multiple cuts exist for a Movie" do
      on_exit_clear_table()

      {movie, _file} = seed_present_movie("Multi-Cut Movie")
      pi_one = playable_item_for_movie(movie)
      # Seed a second cut at position 2.
      {:ok, pi_two} = Library.PlayableItems.find_or_create(:movie, movie.id, 2)

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
      playable_item = playable_item_for_movie(movie)

      assert :undefined = :ets.whereis(@table)

      item = Views.detail(playable_item.id)
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

  describe "Phase 3.2 — expanded fields populated by cold-start refresh" do
    test "Movie row carries :watched_files with path + media_dir" do
      on_exit_clear_table()
      {movie, file} = seed_present_movie("Watched Files Movie")

      assert :ok = Detail.refresh_cache()
      item = Views.detail_by_container(:movie, movie.id)

      assert is_list(item.watched_files)
      assert [%DetailItem.WatchedFile{path: path, media_dir: dir}] = item.watched_files
      assert path == file.file_path
      assert dir == file.media_dir
    end

    test "Movie row carries :container_director (Phase 3.2 Task D)" do
      on_exit_clear_table()
      movie = create_standalone_movie(%{name: "Directed Movie", director: "Sample Director"})
      _file = create_linked_file(%{movie_id: movie.id})

      assert :ok = Detail.refresh_cache()
      item = Views.detail_by_container(:movie, movie.id)

      assert item.container_director == "Sample Director"
    end

    test "Movie row carries :images for entity-owned images" do
      on_exit_clear_table()
      {movie, _file} = seed_present_movie("Image Movie")

      _img =
        create_image(%{
          owner_type: :movie,
          owner_id: movie.id,
          role: "poster",
          content_url: "movies/image-movie/poster.jpg"
        })

      assert :ok = Detail.refresh_cache()
      item = Views.detail_by_container(:movie, movie.id)

      assert is_list(item.images)
      assert Enum.any?(item.images, &(&1.role == "poster"))
    end

    test "TV-series episode row carries :seasons populated with sibling episodes" do
      on_exit_clear_table()
      series = create_tv_series(%{name: "Sample TV Tree"})
      season1 = create_season(%{tv_series_id: series.id, season_number: 1})

      ep1 =
        create_episode(%{
          season_id: season1.id,
          episode_number: 1,
          name: "Pilot",
          duration_seconds: 1800
        })

      ep2 =
        create_episode(%{
          season_id: season1.id,
          episode_number: 2,
          name: "Pilot 2",
          duration_seconds: 1800
        })

      pi1 = create_playable_item_for_episode(ep1)
      pi2 = create_playable_item_for_episode(ep2)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/tv-tree-s01e01.mkv"})
      _f2 = create_linked_file(%{playable_item_id: pi2.id, file_path: "/media/test/tv-tree-s01e02.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail(pi1.id)

      assert is_list(item.seasons)
      assert [%DetailItem.Season{season_number: 1, episodes: episodes}] = item.seasons
      assert length(episodes) == 2
      assert Enum.all?(episodes, &match?(%DetailItem.Episode{}, &1))
      assert Enum.map(episodes, & &1.episode_number) == [1, 2]
      assert Enum.all?(episodes, & &1.present?)
    end

    test "TV-series episodes carry per-episode :images for thumbnail render (Phase 3.2 Task C.2)" do
      on_exit_clear_table()
      series = create_tv_series(%{name: "Sample Thumb Show"})
      season1 = create_season(%{tv_series_id: series.id, season_number: 1})

      ep1 =
        create_episode(%{
          season_id: season1.id,
          episode_number: 1,
          name: "Pilot",
          duration_seconds: 1800
        })

      ep2 =
        create_episode(%{
          season_id: season1.id,
          episode_number: 2,
          name: "Pilot 2",
          duration_seconds: 1800
        })

      pi1 = create_playable_item_for_episode(ep1)
      pi2 = create_playable_item_for_episode(ep2)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/thumb-s01e01.mkv"})
      _f2 = create_linked_file(%{playable_item_id: pi2.id, file_path: "/media/test/thumb-s01e02.mkv"})

      _img1 =
        create_image(%{
          owner_type: :episode,
          owner_id: ep1.id,
          role: "thumb",
          content_url: "episodes/#{ep1.id}/thumb.jpg"
        })

      assert :ok = Detail.refresh_cache()
      item = Views.detail(pi1.id)

      assert [%DetailItem.Season{episodes: [ep1_view, ep2_view]}] = item.seasons
      assert is_list(ep1_view.images)
      assert Enum.any?(ep1_view.images, &(&1.role == "thumb"))
      # Episodes without images still get an empty list — never nil, so
      # `image_url/2` (which dot-accesses `:images`) can't KeyError.
      assert ep2_view.images == []
    end

    test "detail_by_container(:tv_series, id) returns canonical leaf with full seasons tree" do
      on_exit_clear_table()
      series = create_tv_series(%{name: "Sample TV Canonical"})
      season1 = create_season(%{tv_series_id: series.id, season_number: 1})

      ep1 =
        create_episode(%{season_id: season1.id, episode_number: 1, name: "Ep 1", duration_seconds: 1800})

      ep2 =
        create_episode(%{season_id: season1.id, episode_number: 2, name: "Ep 2", duration_seconds: 1800})

      pi1 = create_playable_item_for_episode(ep1)
      pi2 = create_playable_item_for_episode(ep2)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/canon-s01e01.mkv"})
      _f2 = create_linked_file(%{playable_item_id: pi2.id, file_path: "/media/test/canon-s01e02.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail_by_container(:tv_series, series.id)

      refute item == nil
      assert item.playable_item_id == pi1.id
      assert is_list(item.seasons)
      assert [%DetailItem.Season{episodes: episodes}] = item.seasons
      assert length(episodes) == 2
    end

    test "MovieSeries constituent movie row carries :movies" do
      on_exit_clear_table()
      ms = create_movie_series(%{name: "Sample MS Tree"})

      movie1 =
        create_movie(%{
          name: "MS Part 1",
          movie_series_id: ms.id,
          position: 1
        })

      movie2 =
        create_movie(%{
          name: "MS Part 2",
          movie_series_id: ms.id,
          position: 2
        })

      pi1 = create_playable_item_for_movie(movie1)
      pi2 = create_playable_item_for_movie(movie2)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/ms-part-1.mkv"})
      _f2 = create_linked_file(%{playable_item_id: pi2.id, file_path: "/media/test/ms-part-2.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail(pi1.id)

      assert is_list(item.movies)
      assert length(item.movies) == 2
      assert Enum.all?(item.movies, &match?(%DetailItem.MovieEntry{}, &1))
      assert Enum.map(item.movies, & &1.collection_position) == [1, 2]
      assert Enum.all?(item.movies, & &1.present?)
    end

    test "MovieSeries constituent rows tolerate a movie with no WatchedFile (not-yet-acquired)" do
      # Regression: in production this path crashes the Detail projection
      # at boot when a MovieSeries has child movies whose PlayableItem
      # exists (TMDB metadata is in place) but no file has been acquired
      # yet. The build_movies_for_movie_series path used
      # `List.first(files) |> Map.get(:file_path)`, which crashed with
      # BadMapError when files == []. Since the Detail Cache.Worker is in
      # the supervision tree, the crash takes the whole app with it.
      on_exit_clear_table()
      ms = create_movie_series(%{name: "Sample MS Pending File"})

      movie1 =
        create_movie(%{name: "MS Pending Part 1", movie_series_id: ms.id, position: 1})

      movie2 =
        create_movie(%{name: "MS Pending Part 2", movie_series_id: ms.id, position: 2})

      # Part 3 has a PlayableItem (TMDB metadata in place) but no acquired
      # file — the not-yet-acquired constituent that must not crash the
      # collection build. Two present movies (parts 1 & 2) keep this
      # presented as a collection, since the hoist rule needs 2+ possessed.
      movie3 =
        create_movie(%{name: "MS Pending Part 3", movie_series_id: ms.id, position: 3})

      pi1 = create_playable_item_for_movie(movie1)
      pi2 = create_playable_item_for_movie(movie2)
      _pi3 = create_playable_item_for_movie(movie3)

      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/ms-part-1.mkv"})
      _f2 = create_linked_file(%{playable_item_id: pi2.id, file_path: "/media/test/ms-part-2.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail(pi1.id)

      assert item.presented_as == :movie_series
      assert length(item.movies) == 3
      [m1, m2, m3] = item.movies

      assert m1.present?
      assert m1.content_url == "/media/test/ms-part-1.mkv"

      assert m2.present?

      refute m3.present?
      assert m3.content_url == nil
    end

    test "detail_by_container(:movie_series, id) returns canonical leaf with movies list" do
      on_exit_clear_table()
      ms = create_movie_series(%{name: "Sample MS Canonical"})

      movie1 =
        create_movie(%{
          name: "MS Canonical Part 1",
          movie_series_id: ms.id,
          position: 1
        })

      movie2 =
        create_movie(%{
          name: "MS Canonical Part 2",
          movie_series_id: ms.id,
          position: 2
        })

      pi1 = create_playable_item_for_movie(movie1)
      pi2 = create_playable_item_for_movie(movie2)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/ms-canon-1.mkv"})
      _f2 = create_linked_file(%{playable_item_id: pi2.id, file_path: "/media/test/ms-canon-2.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail_by_container(:movie_series, ms.id)

      refute item == nil
      assert item.playable_item_id == pi1.id
      assert is_list(item.movies)
      assert length(item.movies) == 2
    end

    test "movie_series with no own art borrows a child movie's poster + backdrop" do
      on_exit_clear_table()
      ms = create_movie_series(%{name: "Sample MS No Art"})

      movie1 = create_movie(%{name: "No Art Part 1", movie_series_id: ms.id, position: 1})
      movie2 = create_movie(%{name: "No Art Part 2", movie_series_id: ms.id, position: 2})

      # Child movie carries art; the collection itself has none of its own.
      create_image(%{owner_type: :movie, owner_id: movie1.id, role: "poster", content_url: "p.jpg"})
      create_image(%{owner_type: :movie, owner_id: movie1.id, role: "backdrop", content_url: "b.jpg"})

      pi1 = create_playable_item_for_movie(movie1)
      pi2 = create_playable_item_for_movie(movie2)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/no-art-1.mkv"})
      _f2 = create_linked_file(%{playable_item_id: pi2.id, file_path: "/media/test/no-art-2.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail_by_container(:movie_series, ms.id)

      roles = Enum.map(item.images, & &1.role)
      assert "poster" in roles
      assert "backdrop" in roles
    end

    test ":subtitle_tracks defaults to empty list for leaves with no detected tracks" do
      on_exit_clear_table()
      {movie, _file} = seed_present_movie("No Subs Movie")

      assert :ok = Detail.refresh_cache()
      item = Views.detail_by_container(:movie, movie.id)

      assert item.subtitle_tracks == []
    end

    test "Season carries :number_of_episodes from Season schema" do
      on_exit_clear_table()
      series = create_tv_series(%{name: "Sample TV NOE"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, number_of_episodes: 10})

      ep1 =
        create_episode(%{season_id: season.id, episode_number: 1, name: "Ep 1", duration_seconds: 1800})

      pi1 = create_playable_item_for_episode(ep1)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/noe-s01e01.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail(pi1.id)

      assert [%DetailItem.Season{season_number: 1, number_of_episodes: 10}] = item.seasons
    end

    test "Season's :extras is populated from Season's preloaded extras" do
      on_exit_clear_table()
      series = create_tv_series(%{name: "Sample TV Extras"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      _extra =
        create_extra(%{
          owner_type: :season,
          owner_id: season.id,
          name: "Behind the scenes",
          content_url: "tv-extras/sample.mkv"
        })

      ep1 = create_episode(%{season_id: season.id, episode_number: 1, name: "Ep 1"})
      pi1 = create_playable_item_for_episode(ep1)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/extras-s01e01.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail(pi1.id)

      assert [%DetailItem.Season{extras: extras}] = item.seasons
      assert length(extras) == 1
      assert hd(extras).name == "Behind the scenes"
    end

    test "Episode carries :content_url from the first linked WatchedFile" do
      on_exit_clear_table()
      series = create_tv_series(%{name: "Sample TV ContentURL"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      ep1 = create_episode(%{season_id: season.id, episode_number: 1, name: "Ep 1"})
      pi1 = create_playable_item_for_episode(ep1)
      _f1 = create_linked_file(%{playable_item_id: pi1.id, file_path: "/media/test/cu-s01e01.mkv"})

      assert :ok = Detail.refresh_cache()
      item = Views.detail(pi1.id)

      assert [%DetailItem.Season{episodes: [episode]}] = item.seasons
      assert episode.content_url == "/media/test/cu-s01e01.mkv"
    end
  end

  describe "refresh_cache/0 query efficiency (N+1 guard)" do
    test "query count is invariant to the number of episodes under a series" do
      on_exit_clear_table()
      series = create_tv_series(%{name: "Sample N+1 Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      add_present_episode = fn number ->
        episode = create_episode(%{season_id: season.id, episode_number: number})
        playable_item = create_playable_item_for_episode(episode)

        create_linked_file(%{
          playable_item_id: playable_item.id,
          file_path: "/media/test/nplus1-s01e#{number}.mkv"
        })
      end

      Enum.each(1..2, add_present_episode)
      baseline = count_queries(fn -> Detail.refresh_cache() end)

      Enum.each(3..8, add_present_episode)
      grown = count_queries(fn -> Detail.refresh_cache() end)

      assert grown == baseline,
             "refresh_cache issued #{grown} queries for 8 episodes vs #{baseline} for 2 — " <>
               "per-episode queries indicate an N+1 in the projection build"
    end
  end

  defp count_queries(fun) do
    ref = make_ref()
    parent = self()
    handler_id = {:detail_refresh_query_count, ref}

    # Ecto emits `[:repo, :query]` telemetry synchronously in the process
    # that ran the query. Gating on `self() == parent` scopes the count to
    # the test process's own queries, so background Cache.Worker refreshes
    # firing on entity-creation PubSub don't inflate it under full-suite
    # parallelism (see automated-testing skill: telemetry query-counting).
    :ok =
      :telemetry.attach(
        handler_id,
        [:media_centaur, :repo, :query],
        fn _event, _measurements, _metadata, _config ->
          if self() == parent, do: send(parent, {:query, ref})
        end,
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
end
