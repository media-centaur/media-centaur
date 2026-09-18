defmodule MediaCentaur.ReleaseTracking.RefresherTest do
  use MediaCentaur.DataCase, async: false

  import ExUnit.CaptureLog
  import MediaCentaur.TmdbStubs
  alias MediaCentaur.IntegrationAvailability
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

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert hd(releases).air_date == ~D[2026-07-01]
    end

    test "records the show's season sizes on the item — aired count for a fetched season, episode_count for the rest" do
      item = create_tracking_item(%{tmdb_id: 2468, media_type: :tv_series, name: "Sample Show"})

      # Route order matters: `stub_routes/1` matches by prefix, so the
      # season route must precede the show route. Season 1 is asked for
      # too and answered with the show payload (no episode list), which
      # is what an unfetched season looks like.
      stub_routes([
        {"/tv/2468/season/6",
         %{
           "season_number" => 6,
           "episodes" => [
             %{"episode_number" => 1, "name" => "First", "air_date" => "2020-01-01"},
             %{"episode_number" => 2, "name" => "Second", "air_date" => "2099-01-08"}
           ]
         }},
        {"/tv/2468",
         %{
           "id" => 2468,
           "name" => "Sample Show",
           "status" => "Returning Series",
           "number_of_seasons" => 6,
           "next_episode_to_air" => %{
             "air_date" => "2099-01-08",
             "season_number" => 6,
             "episode_number" => 2,
             "name" => "Second"
           },
           "seasons" => [
             %{"season_number" => 0, "episode_count" => 4},
             %{"season_number" => 1, "episode_count" => 22},
             %{"season_number" => 6, "episode_count" => 13}
           ]
         }}
      ])

      :ok = Refresher.refresh_item(item)

      assert ReleaseTracking.get_item(item.id).season_sizes == %{"1" => 22, "6" => 1}
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

  describe "held work — a known-down TMDB is not asked" do
    setup do
      test_pid = self()

      Req.Test.stub(:tmdb, fn conn ->
        send(test_pid, {:tmdb_called, conn.request_path})
        Req.Test.json(conn, %{"id" => 2468, "name" => "Sample Show"})
      end)

      create_tracking_item(%{tmdb_id: 2468, media_type: :tv_series, name: "Sample Show"})
      pid = start_supervised!(Refresher)

      {:ok, pid: pid}
    end

    test "a refresh tick makes no TMDB request while TMDB is down", %{pid: pid} do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      send(pid, :refresh)
      # A call behind the cast: the tick above is handled first.
      assert :ok = Refresher.__tick_for_test__(fn -> :ok end)

      refute_received {:tmdb_called, _path}
    end

    test "TMDB answering again runs the cycle the outage held", %{pid: pid} do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      send(pid, :refresh)
      assert :ok = Refresher.__tick_for_test__(fn -> :ok end)
      refute_received {:tmdb_called, _path}

      {:changed, :up} = IntegrationAvailability.report(:tmdb, :up)
      assert :ok = Refresher.__tick_for_test__(fn -> :ok end)

      assert_received {:tmdb_called, "/3/tv/2468"}
    end

    test "TMDB answering with nothing deferred runs nothing", %{pid: pid} do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})
      {:changed, :up} = IntegrationAvailability.report(:tmdb, :up)

      assert :ok = Refresher.__tick_for_test__(fn -> :ok end)
      assert Process.alive?(pid)

      refute_received {:tmdb_called, _path}
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
      assert ReleaseTracking.get_item_by_tmdb(303_030, :movie) == nil
      assert_received {:item_removed, "303030", "movie"}

      :ok = ReleaseTracking.complete_movie_tracking_for([movie.id])
      refute_received {:item_removed, "303030", "movie"}
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
