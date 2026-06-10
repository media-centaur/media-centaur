defmodule MediaCentaur.ReleaseTracking.WantsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Refresher
  alias MediaCentaur.ReleaseTracking.Want

  @yesterday Date.add(Date.utc_today(), -1)
  @last_month Date.add(Date.utc_today(), -30)
  @tomorrow Date.add(Date.utc_today(), 1)

  defp create_tv_item(attrs \\ %{}) do
    create_tracking_item(Map.merge(%{media_type: :tv_series, name: "Sample Show"}, attrs))
  end

  defp create_episode_release(item, attrs \\ %{}) do
    defaults = %{
      item_id: item.id,
      air_date: @yesterday,
      title: "Sample Episode",
      season_number: 1,
      episode_number: 1,
      released: true,
      in_library: false
    }

    ReleaseTracking.create_release!(Map.merge(defaults, attrs))
  end

  describe "sync_wants/1 — opening calendar wants" do
    test "opens an open want for a released, not-in-library episode" do
      item = create_tv_item()
      create_episode_release(item, %{season_number: 2, episode_number: 5, air_date: @last_month})

      :ok = ReleaseTracking.sync_wants(item)

      assert [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert want.status == :open
      assert want.provenance == :calendar
      assert want.season_number == 2
      assert want.episode_number == 5
      assert want.air_date == @last_month
      assert want.title == "Sample Episode"
      assert is_nil(want.last_searched_at)
    end

    test "wanted_since is the air date for releases aired before today" do
      item = create_tv_item()
      create_episode_release(item, %{air_date: @last_month})

      :ok = ReleaseTracking.sync_wants(item)

      [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert DateTime.to_date(want.wanted_since) == @last_month
    end

    test "wanted_since is now for releases airing today" do
      item = create_tv_item()
      create_episode_release(item, %{air_date: Date.utc_today()})

      :ok = ReleaseTracking.sync_wants(item)

      [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert DateTime.diff(DateTime.utc_now(), want.wanted_since, :second) < 60
    end

    test "does not open wants for unaired releases" do
      item = create_tv_item()
      create_episode_release(item, %{air_date: @tomorrow, released: false})

      :ok = ReleaseTracking.sync_wants(item)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
    end

    test "does not open wants for in-library releases" do
      item = create_tv_item()
      create_episode_release(item, %{in_library: true})

      :ok = ReleaseTracking.sync_wants(item)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
    end

    test "does not open wants for releases aired before dismiss_released_before" do
      item = create_tv_item()
      {:ok, item} = ReleaseTracking.update_item(item, %{dismiss_released_before: @yesterday})
      create_episode_release(item, %{air_date: @last_month})

      :ok = ReleaseTracking.sync_wants(item)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
    end

    test "is idempotent — re-syncing creates no duplicate wants" do
      item = create_tv_item()
      create_episode_release(item)

      :ok = ReleaseTracking.sync_wants(item)
      :ok = ReleaseTracking.sync_wants(item)

      assert [_only_one] = ReleaseTracking.open_wants_for_item(item.id)
    end

    test "does not reopen a dismissed want" do
      item = create_tv_item()
      create_episode_release(item, %{air_date: @last_month})

      :ok = ReleaseTracking.sync_wants(item)
      {:ok, item} = ReleaseTracking.update_item(item, %{dismiss_released_before: Date.utc_today()})
      ReleaseTracking.dismiss_wants_before(item, Date.utc_today())
      assert ReleaseTracking.open_wants_for_item(item.id) == []

      :ok = ReleaseTracking.sync_wants(item)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
    end

    test "skips ignored items entirely" do
      item = create_tv_item()
      create_episode_release(item)
      {:ok, ignored} = ReleaseTracking.ignore_item(item)

      :ok = ReleaseTracking.sync_wants(ignored)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
    end
  end

  describe "sync_wants/1 — movie wants" do
    test "opens one want keyed by part_tmdb_id once an acquirable date has passed" do
      item = create_tracking_item(%{media_type: :movie, name: "Sample Movie", tmdb_id: 603})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @last_month,
        title: "Sample Movie",
        release_type: "theatrical",
        part_tmdb_id: 603,
        released: true
      })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @yesterday,
        title: "Sample Movie",
        release_type: "digital",
        part_tmdb_id: 603,
        released: true
      })

      :ok = ReleaseTracking.sync_wants(item)

      assert [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert want.part_tmdb_id == 603
      assert is_nil(want.season_number)
      # The want anchors on the earliest acquirable date (digital), not theatrical.
      assert want.air_date == @yesterday
    end

    test "opens no want for a theatrical-only release" do
      item = create_tracking_item(%{media_type: :movie, name: "Theater Movie", tmdb_id: 604})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @yesterday,
        title: "Theater Movie",
        release_type: "theatrical",
        part_tmdb_id: 604,
        released: true
      })

      :ok = ReleaseTracking.sync_wants(item)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
    end

    test "collection part rows (untyped) open a want carrying the part id" do
      item = create_tracking_item(%{media_type: :movie, name: "Sample Saga", tmdb_id: 1000})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @yesterday,
        title: "Sample Saga Part II",
        part_tmdb_id: 2002,
        released: true
      })

      :ok = ReleaseTracking.sync_wants(item)

      assert [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert want.part_tmdb_id == 2002
      assert want.title == "Sample Saga Part II"
    end

    test "legacy solo-movie rows without part_tmdb_id fall back to the item tmdb_id" do
      item = create_tracking_item(%{media_type: :movie, name: "Legacy Movie", tmdb_id: 605})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @yesterday,
        title: "Legacy Movie",
        release_type: "digital",
        released: true
      })

      :ok = ReleaseTracking.sync_wants(item)

      assert [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert want.part_tmdb_id == 605
    end

    test "legacy collection rows without part_tmdb_id are skipped until the refresher stamps them" do
      item = create_tracking_item(%{media_type: :movie, name: "Legacy Saga", tmdb_id: 1001})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @yesterday,
        title: "Legacy Saga Part III",
        released: true
      })

      :ok = ReleaseTracking.sync_wants(item)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
    end
  end

  describe "sync_wants/1 — satisfaction by library presence" do
    test "satisfies a TV want when the linked library series gains the episode" do
      tv_series = create_tv_series(%{name: "Sample Show"})

      item =
        create_tv_item(%{
          library_container_type: :tv_series,
          library_container_id: tv_series.id
        })

      create_episode_release(item, %{season_number: 1, episode_number: 3, air_date: @last_month})
      :ok = ReleaseTracking.sync_wants(item)
      assert [%{status: :open}] = ReleaseTracking.open_wants_for_item(item.id)

      # The episode lands in the library (any path: pursuit, naked
      # search, disk import) — the next sync closes the want.
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 3, name: "Third"})

      create_linked_file(%{
        playable_item: %{id: playable_item_id_for_episode(episode)},
        file_path: "/media/test/Sample.Show.S01E03.1080p.WEB-DL.mkv"
      })

      :ok = ReleaseTracking.sync_wants(item)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
      [want] = all_wants_for_item(item.id)
      assert want.status == :satisfied
      assert want.satisfied_at
      assert want.satisfied_quality == "hd_1080p"
    end

    test "satisfies a movie want when a library movie carries the matching tmdb id" do
      movie_series = create_movie_series(%{name: "Sample Saga"})
      movie = create_movie(%{movie_series_id: movie_series.id, name: "Sample Saga Part II"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "2002"})

      item = create_tracking_item(%{media_type: :movie, name: "Sample Saga", tmdb_id: 1000})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @yesterday,
        title: "Sample Saga Part II",
        part_tmdb_id: 2002,
        released: true
      })

      :ok = ReleaseTracking.sync_wants(item)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
      [want] = all_wants_for_item(item.id)
      assert want.status == :satisfied
      assert want.satisfied_at
    end

    test "an unlinked TV item never satisfies wants" do
      item = create_tv_item()
      create_episode_release(item, %{season_number: 1, episode_number: 1})

      :ok = ReleaseTracking.sync_wants(item)

      assert [%{status: :open}] = ReleaseTracking.open_wants_for_item(item.id)
    end
  end

  describe "dismissals" do
    test "dismiss_wants_before/2 dismisses open wants aired before the cutoff" do
      item = create_tv_item()
      create_episode_release(item, %{season_number: 1, episode_number: 1, air_date: @last_month})
      create_episode_release(item, %{season_number: 1, episode_number: 2, air_date: Date.utc_today()})
      :ok = ReleaseTracking.sync_wants(item)

      ReleaseTracking.dismiss_wants_before(item, @yesterday)

      assert [open] = ReleaseTracking.open_wants_for_item(item.id)
      assert open.episode_number == 2

      dismissed = Enum.find(all_wants_for_item(item.id), &(&1.status == :dismissed))
      assert dismissed.episode_number == 1
      assert dismissed.dismissed_at
    end

    test "dismiss_release/1 dismisses the matching want" do
      item = create_tv_item()
      release = create_episode_release(item, %{season_number: 3, episode_number: 7})
      :ok = ReleaseTracking.sync_wants(item)

      {:ok, _} = ReleaseTracking.dismiss_release(release.id)

      assert ReleaseTracking.open_wants_for_item(item.id) == []
      assert [%{status: :dismissed}] = all_wants_for_item(item.id)
    end

    test "deleting an item deletes its wants" do
      item = create_tv_item()
      create_episode_release(item)
      :ok = ReleaseTracking.sync_wants(item)
      assert [_] = all_wants_for_item(item.id)

      {:ok, _} = ReleaseTracking.delete_item(item)

      assert all_wants_for_item(item.id) == []
    end
  end

  describe "queries" do
    test "list_open_wants/0 returns wants of watching items only" do
      watching = create_tv_item(%{tmdb_id: 111, name: "Watching Show"})
      create_episode_release(watching)
      :ok = ReleaseTracking.sync_wants(watching)

      later_ignored = create_tv_item(%{tmdb_id: 222, name: "Ignored Show"})
      create_episode_release(later_ignored)
      :ok = ReleaseTracking.sync_wants(later_ignored)
      {:ok, _} = ReleaseTracking.ignore_item(later_ignored)

      open = ReleaseTracking.list_open_wants()
      assert Enum.map(open, & &1.item_id) == [watching.id]
    end
  end

  describe "change broadcasts" do
    test "a sync that opens or satisfies wants broadcasts releases_updated" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "release_tracking:updates")

      item = create_tv_item(%{tmdb_id: 444, name: "Broadcast Show"})
      create_episode_release(item)

      :ok = ReleaseTracking.sync_wants(item)
      item_id = item.id
      assert_received {:releases_updated, [^item_id]}

      # Unchanged re-sync stays silent — the sweep must not churn views.
      :ok = ReleaseTracking.sync_wants(item)
      refute_received {:releases_updated, [^item_id]}
    end
  end

  describe "sweep integration" do
    test "sweep_now/0 opens wants for newly released episodes" do
      item = create_tv_item(%{tmdb_id: 333, name: "Sweep Show"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: @yesterday,
        title: "Just Aired",
        season_number: 4,
        episode_number: 1,
        released: false
      })

      Refresher.sweep_now()

      assert [want] = ReleaseTracking.open_wants_for_item(item.id)
      assert want.season_number == 4
      assert want.episode_number == 1
    end
  end

  defp all_wants_for_item(item_id) do
    Repo.all(from(w in Want, where: w.item_id == ^item_id))
  end

  defp playable_item_id_for_episode(episode) do
    {:ok, playable_item} =
      Library.create_playable_item(%{
        container_type: :episode,
        container_id: episode.id,
        position: episode.episode_number || 1,
        name: episode.name
      })

    playable_item.id
  end
end
