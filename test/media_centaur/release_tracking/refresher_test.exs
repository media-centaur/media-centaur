defmodule MediaCentaur.ReleaseTracking.RefresherTest do
  use MediaCentaur.DataCase, async: false

  import ExUnit.CaptureLog
  import MediaCentaur.TmdbStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Refresher
  alias MediaCentaur.ReleaseTracking.Release

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "refresh_item/1" do
    test "updates releases and detects date changes for TV series" do
      item = create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show"})

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
           "name" => "Sample Show",
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
      # A collection is a movie item linked to a library MovieSeries.
      item =
        create_tracking_item(%{
          tmdb_id: 263,
          media_type: :movie,
          name: "Sample Collection",
          library_container_type: :movie_series,
          library_container_id: Ecto.UUID.generate()
        })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: ~D[2028-07-01],
        title: "Sample Movie B"
      })

      stub_routes([
        {"/collection/263",
         %{
           "id" => 263,
           "name" => "Sample Collection",
           "poster_path" => "/dk.jpg",
           "parts" => [
             %{"id" => 155, "title" => "Sample Movie A", "release_date" => "2008-07-18"},
             %{
               "id" => 99_999,
               "title" => "Sample Movie B",
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
      refute Release.released?(hd(releases))
    end

    test "a solo movie tracker fetches /movie/{id} — it is not linked to a collection" do
      item =
        create_tracking_item(%{
          tmdb_id: 1_226_863,
          media_type: :movie,
          name: "Solo Movie"
        })

      # Both resources answer; only the movie one is the right resource for
      # an item with no MovieSeries link, and only its date may land.
      stub_routes([
        {"/collection/1226863",
         %{
           "id" => 1_226_863,
           "name" => "Wrong Resource",
           "parts" => [%{"id" => 1, "title" => "Part", "release_date" => "2030-01-01"}]
         }},
        {"/movie/1226863",
         %{
           "id" => 1_226_863,
           "title" => "Solo Movie",
           "release_date" => "2027-12-25",
           "poster_path" => "/sm.jpg",
           "backdrop_path" => "/sm-bd.jpg"
         }}
      ])

      :ok = Refresher.refresh_item(item)

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 1
      assert hd(releases).air_date == ~D[2027-12-25]
      assert hd(releases).title == "Solo Movie"

      reloaded = ReleaseTracking.get_item(item.id)
      assert reloaded.name == "Solo Movie"
    end
  end

  describe "a timer tick that fails" do
    test "is logged and leaves the Refresher running for the next tick" do
      pid = start_supervised!(Refresher)

      log =
        capture_log(fn ->
          assert :error = Refresher.__tick_for_test__(fn -> raise "sweep exploded" end)
        end)

      assert Process.alive?(pid)
      assert log =~ "release tracking: test tick failed"
      assert log =~ "sweep exploded"
    end

    test "an exit inside the tick is contained the same way" do
      pid = start_supervised!(Refresher)

      log =
        capture_log(fn ->
          assert :error = Refresher.__tick_for_test__(fn -> exit(:db_gone) end)
        end)

      assert Process.alive?(pid)
      assert log =~ "release tracking: test tick failed"
      assert log =~ "db_gone"
    end
  end

  describe "sweep_now/0" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "release_tracking:updates")
      :ok
    end

    test "marks releases with past air dates as released" do
      item = create_tracking_item(%{tmdb_id: 7777, media_type: :tv_series, name: "Sweep Target"})
      yesterday = Date.add(Date.utc_today(), -1)
      tomorrow = Date.add(Date.utc_today(), 1)

      past_release =
        ReleaseTracking.create_release!(%{
          item_id: item.id,
          air_date: yesterday,
          title: "Aired",
          season_number: 1,
          episode_number: 1,
          released: false
        })

      future_release =
        ReleaseTracking.create_release!(%{
          item_id: item.id,
          air_date: tomorrow,
          title: "Upcoming",
          season_number: 1,
          episode_number: 2,
          released: false
        })

      Refresher.sweep_now()

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Release.released?(Enum.find(releases, &(&1.id == past_release.id)))
      refute Release.released?(Enum.find(releases, &(&1.id == future_release.id)))
    end

    test "broadcasts {:tracking_sweep_completed} — the drop planner's clock and the ComingUp refresh signal" do
      Refresher.sweep_now()

      assert_received {:tracking_sweep_completed}
    end

    test "persists last_swept_at in Settings as a parseable ISO8601 timestamp" do
      Refresher.sweep_now()

      entry = MediaCentaur.Settings.get_by_key("release_tracking:last_swept_at")
      assert %{value: %{"timestamp" => timestamp_string}} = entry
      assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(timestamp_string)
    end
  end

  describe "complete_movie_tracking_for/1" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "release_tracking:updates")
      :ok
    end

    test "removes movie tracking item when matching library Movie is created" do
      movie = create_standalone_movie(%{name: "Solo Movie", tmdb_id: "424242"})

      item =
        create_tracking_item(%{
          tmdb_id: 424_242,
          media_type: :movie,
          name: "Solo Movie",
          source: :manual
        })

      :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])

      assert ReleaseTracking.get_item(item.id) == nil
      assert ReleaseTracking.get_item_by_tmdb(424_242, :movie) == nil

      events = ReleaseTracking.list_recent_events(5)

      assert Enum.any?(events, fn event ->
               event.event_type == :stopped_tracking and event.item_name == "Solo Movie"
             end)

      assert_received {:item_removed, "424242", "movie"}
    end

    test "does not remove TV series tracking when a TV series library entity arrives" do
      tv_series = create_tv_series(%{name: "Active Series", tmdb_id: "55555"})

      item =
        create_tracking_item(%{
          tmdb_id: 55_555,
          media_type: :tv_series,
          name: "Active Series"
        })

      :ok = ReleaseTracking.complete_movie_tracking_for([tv_series.id])

      assert ReleaseTracking.get_item(item.id) != nil
    end

    test "does not remove movie-collection tracking when an unrelated movie arrives" do
      movie = create_standalone_movie(%{name: "Single Film", tmdb_id: "111"})

      # Tracking item points at a TMDB collection id (different number space)
      item =
        create_tracking_item(%{
          tmdb_id: 999,
          media_type: :movie,
          name: "Some Collection",
          source: :manual
        })

      :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])

      assert ReleaseTracking.get_item(item.id) != nil
    end

    test "is idempotent — second call after removal is a no-op" do
      movie = create_standalone_movie(%{name: "Idempotent Movie", tmdb_id: "303030"})

      create_tracking_item(%{
        tmdb_id: 303_030,
        media_type: :movie,
        name: "Idempotent Movie",
        source: :manual
      })

      :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])
      events_after_first = ReleaseTracking.list_recent_events(10)

      :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])
      events_after_second = ReleaseTracking.list_recent_events(10)

      stopped_count = fn events ->
        Enum.count(events, &(&1.event_type == :stopped_tracking))
      end

      assert stopped_count.(events_after_first) == stopped_count.(events_after_second)
    end

    test "ignores library movies without a tmdb_id" do
      movie = create_standalone_movie(%{name: "Manual Import", tmdb_id: nil})

      item =
        create_tracking_item(%{
          tmdb_id: 777,
          media_type: :movie,
          name: "Other Movie",
          source: :manual
        })

      :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])

      assert ReleaseTracking.get_item(item.id) != nil
    end
  end
end
