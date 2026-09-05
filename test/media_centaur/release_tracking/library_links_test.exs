defmodule MediaCentaur.ReleaseTracking.LibraryLinksTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.LibraryLinks

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "refresh_for/1 — auto-linking" do
    test "links a manually-tracked item to a library entity by TMDB ID and updates episode progress" do
      tv_series = create_tv_series(%{name: "Sample Drama", tmdb_id: "250307"})

      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 2, number_of_episodes: 14})

      for ep <- 1..14 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      # Manually-tracked item with no library_container_id — simulates the real scenario
      item =
        create_tracking_item(%{
          tmdb_id: 250_307,
          media_type: :tv_series,
          name: "Sample Drama",
          source: :manual,
          last_library_season: 2,
          last_library_episode: 13
        })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -1),
        title: "8:00 P.M.",
        season_number: 2,
        episode_number: 14,
        released: true
      })

      LibraryLinks.refresh_for([tv_series.id])

      updated = ReleaseTracking.get_item(item.id)
      assert updated.library_container_type == :tv_series
      assert updated.library_container_id == tv_series.id
      assert updated.last_library_episode == 14

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Enum.all?(releases, & &1.in_library)
    end

    test "does not affect items already linked to a library container" do
      tv_series = create_tv_series(%{name: "Already Linked", tmdb_id: "11111"})

      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 5})

      for ep <- 1..5 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      item =
        create_tracking_item(%{
          tmdb_id: 11_111,
          media_type: :tv_series,
          name: "Already Linked",
          library_container_type: :tv_series,
          library_container_id: tv_series.id,
          last_library_season: 1,
          last_library_episode: 4
        })

      LibraryLinks.refresh_for([tv_series.id])

      updated = ReleaseTracking.get_item(item.id)
      assert updated.library_container_type == :tv_series
      assert updated.library_container_id == tv_series.id
      assert updated.last_library_episode == 5
    end
  end

  describe "refresh_for/1 — episode progress" do
    test "removes tracking item when library entity is deleted" do
      tv_series = create_tv_series(%{name: "Cancelled Show"})

      item =
        create_tracking_item(%{
          tmdb_id: 9999,
          media_type: :tv_series,
          name: "Cancelled Show",
          library_container_type: :tv_series,
          library_container_id: tv_series.id
        })

      # Delete the library entity
      MediaCentaur.Library.Containers.destroy(tv_series)

      # Simulate PubSub event — call the function directly since GenServer isn't running in test
      LibraryLinks.refresh_for([tv_series.id])

      assert ReleaseTracking.get_item(item.id) == nil
    end

    test "updates last_library_season/episode when new episodes added" do
      tv_series = create_tv_series(%{name: "Active Show"})

      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 5})

      for ep <- 1..5 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      item =
        create_tracking_item(%{
          tmdb_id: 8888,
          media_type: :tv_series,
          name: "Active Show",
          library_container_type: :tv_series,
          library_container_id: tv_series.id,
          last_library_season: 1,
          last_library_episode: 3
        })

      # Simulate PubSub event
      LibraryLinks.refresh_for([tv_series.id])

      updated = ReleaseTracking.get_item(item.id)
      assert updated.last_library_season == 1
      assert updated.last_library_episode == 5
    end

    test "marks releases in_library and broadcasts when new episode added" do
      tv_series = create_tv_series(%{name: "Sample Comedy"})

      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 3, number_of_episodes: 9})

      for ep <- 1..9 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      item =
        create_tracking_item(%{
          tmdb_id: 4321,
          media_type: :tv_series,
          name: "Sample Comedy",
          library_container_type: :tv_series,
          library_container_id: tv_series.id,
          last_library_season: 3,
          last_library_episode: 8
        })

      # Create a release for S03E09 that should get marked in_library
      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -1),
        title: "Episode 9",
        season_number: 3,
        episode_number: 9,
        released: true
      })

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "release_tracking:updates")

      # Simulate library change event
      LibraryLinks.refresh_for([tv_series.id])

      # Release should be marked in_library
      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Enum.all?(releases, & &1.in_library)

      # LiveView should be notified via PubSub
      assert_received {:releases_updated, _item_ids}
    end
  end
end
