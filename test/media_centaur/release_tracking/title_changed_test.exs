defmodule MediaCentaur.ReleaseTracking.TitleChangedTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TmdbStubs

  # Ready and with an artwork cache, so the rebuild's artwork downloads
  # land on the stub; every test awaits them (ADR-049).
  setup do
    TmdbStubs.setup_tmdb_client()
    TmdbStubs.setup_artwork_cache()
    TmdbStubs.mark_ready!()
    ReleaseTracking.subscribe()
    :ok
  end

  test "a changed tracked series rebuilds its calendar from the stored season" do
    series =
      TmdbStubs.tv_detail(%{
        "id" => 900,
        "status" => "Returning Series",
        "number_of_seasons" => 1,
        "seasons" => [%{"season_number" => 1, "episode_count" => 3}]
      })

    item =
      create_tracking_item(%{
        tmdb_id: 900,
        media_type: :tv_series,
        payload: series,
        last_library_season: 1,
        last_library_episode: 2
      })

    season =
      TmdbStubs.season_detail(%{
        "season_number" => 1,
        "episodes" => [
          %{"episode_number" => 2, "name" => "Two", "air_date" => "2026-01-01"},
          %{"episode_number" => 3, "name" => "Three", "air_date" => "2026-12-01"}
        ]
      })

    create_season_record(%{tmdb_id: 900, season_number: 1, payload: season})

    assert :ok = ReleaseTracking.title_changed({900, :tv_series})
    await_supervised_tasks()

    assert [%{episode_number: 3, air_date: ~D[2026-12-01]}] =
             ReleaseTracking.list_releases_for_item(item.id)

    assert_receive {:releases_updated, [item_id]}
    assert item_id == item.id
  end

  test "a changed tracked movie rebuilds its typed dates" do
    item =
      create_tracking_item(%{
        tmdb_id: 901,
        media_type: :movie,
        payload: TmdbStubs.movie_detail(%{"id" => 901, "release_date" => "2026-11-11"})
      })

    assert :ok = ReleaseTracking.title_changed({901, :movie})
    await_supervised_tasks()

    assert [%{release_type: "theatrical", air_date: ~D[2026-11-11]}] =
             ReleaseTracking.list_releases_for_item(item.id)
  end

  test "a title nobody tracks is ignored" do
    create_title_record(%{tmdb_id: 902, media_type: :movie})
    assert :ok = ReleaseTracking.title_changed({902, :movie})
    refute_receive {:releases_updated, _ids}
  end

  test "a wanted season the store lacks is first-contacted before the rebuild" do
    test_pid = self()

    Req.Test.stub(:tmdb, fn conn ->
      send(test_pid, {:tmdb_hit, conn.request_path})

      # Season 1 has aired in full; season 2 holds the one episode ahead.
      season =
        if String.ends_with?(conn.request_path, "/season/1"),
          do: %{
            "season_number" => 1,
            "episodes" =>
              Enum.map(1..10, fn number ->
                %{
                  "episode_number" => number,
                  "name" => "S1E#{number}",
                  "air_date" => "2025-01-0#{rem(number, 9) + 1}"
                }
              end)
          },
          else: %{
            "season_number" => 2,
            "episodes" => [%{"episode_number" => 1, "name" => "S2E1", "air_date" => "2026-12-24"}]
          }

      Req.Test.json(conn, TmdbStubs.season_detail(season))
    end)

    series =
      TmdbStubs.tv_detail(%{
        "id" => 903,
        "status" => "Returning Series",
        "number_of_seasons" => 2,
        "next_episode_to_air" => %{
          "air_date" => "2026-12-24",
          "season_number" => 2,
          "episode_number" => 1
        },
        "seasons" => [
          %{"season_number" => 1, "episode_count" => 10},
          %{"season_number" => 2, "episode_count" => 10}
        ]
      })

    item =
      create_tracking_item(%{
        tmdb_id: 903,
        media_type: :tv_series,
        payload: series,
        last_library_season: 1,
        last_library_episode: 10
      })

    assert :ok = ReleaseTracking.title_changed({903, :tv_series})
    await_supervised_tasks()
    assert_receive {:tmdb_hit, "/3/tv/903/season/2"}
    assert [%{season_number: 2, episode_number: 1}] = ReleaseTracking.list_releases_for_item(item.id)
  end
end
