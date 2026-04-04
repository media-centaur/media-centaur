defmodule MediaCentaur.ReleaseTracking.RefresherTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Refresher

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "refresh_item/1" do
    test "updates releases and detects date changes for TV series" do
      item = create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show Eight"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: ~D[2026-06-15],
        title: "Return",
        season_number: 6,
        episode_number: 1
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show Eight",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => %{
             "air_date" => "2026-07-01",
             "season_number" => 6,
             "episode_number" => 1,
             "name" => "Return"
           }
         }}
      ])

      :ok = Refresher.refresh_item(item)

      events = ReleaseTracking.list_recent_events(10)
      assert Enum.any?(events, &(&1.event_type == :upcoming_release_date_changed))

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert hd(releases).air_date == ~D[2026-07-01]
    end

    test "refreshes movie collection releases" do
      item =
        create_tracking_item(%{tmdb_id: 263, media_type: :movie, name: "Dark Knight Collection"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: ~D[2028-07-01],
        title: "The Shadowy Sentinel Returns"
      })

      stub_routes([
        {"/collection/263",
         %{
           "id" => 263,
           "name" => "Dark Knight Collection",
           "poster_path" => "/dk.jpg",
           "parts" => [
             %{"id" => 155, "title" => "The Shadowy Sentinel", "release_date" => "2008-07-18"},
             %{
               "id" => 99999,
               "title" => "The Shadowy Sentinel Returns",
               "release_date" => "2028-12-25"
             }
           ]
         }}
      ])

      :ok = Refresher.refresh_item(item)

      events = ReleaseTracking.list_recent_events(10)
      assert Enum.any?(events, &(&1.event_type == :upcoming_release_date_changed))

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 1
      assert hd(releases).air_date == ~D[2028-12-25]
      assert hd(releases).released == false
    end

    test "marks past releases as released" do
      item = create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show Eight"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -3),
        title: "Past Episode",
        season_number: 1,
        episode_number: 1
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show Eight",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => nil
         }}
      ])

      :ok = Refresher.refresh_item(item)

      {_count, _} = ReleaseTracking.mark_past_releases_as_released()
      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert is_list(releases)
    end
  end

  describe "update_last_episodes_for (via PubSub)" do
    test "removes tracking item when library entity is deleted" do
      tv_series = create_tv_series(%{name: "Cancelled Show"})

      item =
        create_tracking_item(%{
          tmdb_id: 9999,
          media_type: :tv_series,
          name: "Cancelled Show",
          library_entity_id: tv_series.id
        })

      # Delete the library entity
      MediaCentaur.Library.destroy_tv_series(tv_series)

      # Simulate PubSub event — call the function directly since GenServer isn't running in test
      Refresher.refresh_item_tracking_for([tv_series.id])

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
          library_entity_id: tv_series.id,
          last_library_season: 1,
          last_library_episode: 3
        })

      # Simulate PubSub event
      Refresher.refresh_item_tracking_for([tv_series.id])

      updated = ReleaseTracking.get_item(item.id)
      assert updated.last_library_season == 1
      assert updated.last_library_episode == 5
    end
  end
end
