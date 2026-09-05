defmodule MediaCentaur.ReleaseTracking.AutoTrackTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.AutoTrack

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "run/1" do
    test "auto-tracks a returning TV series with a TMDB ID" do
      tv_series = create_tv_series(%{name: "New Show", status: :returning})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "5555"
      })

      stub_routes([
        {"/tv/5555",
         %{
           "id" => 5555,
           "name" => "New Show",
           "status" => "Returning Series",
           "poster_path" => "/new.jpg",
           "number_of_seasons" => 2,
           "next_episode_to_air" => %{
             "air_date" => "2026-07-01",
             "season_number" => 3,
             "episode_number" => 1,
             "name" => "Premiere"
           }
         }}
      ])

      AutoTrack.run([tv_series.id])

      item = ReleaseTracking.get_item_by_tmdb(5555, :tv_series)
      assert item != nil
      assert item.name == "New Show"
      assert item.source == :library
      assert item.library_container_type == :tv_series
      assert item.library_container_id == tv_series.id

      releases = ReleaseTracking.list_releases_for_item(item.id)
      refute releases == []

      events = ReleaseTracking.list_recent_events(5)
      assert Enum.any?(events, &(&1.event_type == :began_tracking))
    end

    test "skips ended TV series" do
      tv_series = create_tv_series(%{name: "Done Show", status: :ended})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "6666"
      })

      AutoTrack.run([tv_series.id])

      assert ReleaseTracking.get_item_by_tmdb(6666, :tv_series) == nil
    end

    test "skips TV series without TMDB external ID" do
      tv_series = create_tv_series(%{name: "No TMDB", status: :returning})

      AutoTrack.run([tv_series.id])

      # No tracking item created (no TMDB ID to track)
      items = ReleaseTracking.list_all_items()
      refute Enum.any?(items, &(&1.name == "No TMDB"))
    end

    test "skips TV series already tracked" do
      tv_series = create_tv_series(%{name: "Already Tracked", status: :returning})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "7777"
      })

      create_tracking_item(%{
        tmdb_id: 7777,
        media_type: :tv_series,
        name: "Already Tracked",
        library_container_type: :tv_series,
        library_container_id: tv_series.id
      })

      AutoTrack.run([tv_series.id])

      # Still just one tracking item
      items = ReleaseTracking.list_all_items()
      assert length(Enum.filter(items, &(&1.tmdb_id == 7777))) == 1
    end

    test "skips TV series with nil status" do
      tv_series = create_tv_series(%{name: "Unknown Status"})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "8888"
      })

      AutoTrack.run([tv_series.id])

      assert ReleaseTracking.get_item_by_tmdb(8888, :tv_series) == nil
    end
  end
end
