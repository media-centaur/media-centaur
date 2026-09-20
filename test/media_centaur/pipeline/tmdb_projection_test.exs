defmodule MediaCentaur.Pipeline.TmdbProjectionTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Containers
  alias MediaCentaur.Library.Events.EntitiesChanged
  alias MediaCentaur.Library.ExternalId
  alias MediaCentaur.Pipeline.TmdbProjection
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Store

  setup do
    TmdbStubs.setup_tmdb_client()
    Library.subscribe()
    :ok
  end

  describe "reapply/1 — a movie" do
    test "its TMDB fields follow the store; its credits do not" do
      movie =
        create_movie(%{
          name: "Old Name",
          tmdb_id: "550",
          cast: [%{"name" => "Kept Actor", "character" => "Lead"}]
        })

      create_title_record(%{
        tmdb_id: 550,
        media_type: :movie,
        payload:
          TmdbStubs.movie_detail(%{
            "id" => 550,
            "title" => "New Name",
            "overview" => "New overview.",
            "status" => "Released",
            "imdb_id" => "tt0000550"
          })
      })

      assert :ok = TmdbProjection.reapply({550, :movie})

      {:ok, updated} = Containers.fetch(:movie, movie.id)
      assert updated.name == "New Name"
      assert updated.description == "New overview."
      assert updated.status == :released
      assert [%{name: "Kept Actor"}] = updated.cast

      assert %ExternalId{external_id: "tt0000550"} =
               Repo.get_by(ExternalId, owner_id: movie.id, source: "imdb")

      assert_receive {:entities_changed, %EntitiesChanged{entity_ids: ids}}
      assert movie.id in ids
    end

    test "a title the library does not own is a no-op" do
      create_title_record(%{tmdb_id: 551, media_type: :movie})

      assert :ok = TmdbProjection.reapply({551, :movie})
      refute_receive {:entities_changed, _event}
    end

    test "a title the store does not hold is a no-op" do
      create_movie(%{name: "Sample Movie", tmdb_id: "552"})

      assert :ok = TmdbProjection.reapply({552, :movie})
      refute_receive {:entities_changed, _event}
    end
  end

  describe "reapply/1 — a series" do
    test "its fields, each season's list and each episode's details follow the store; membership and unknown episodes do not" do
      series = create_tv_series(%{name: "Old Show", tmdb_id: "1396", status: :returning})

      season =
        create_season(%{
          tv_series_id: series.id,
          season_number: 1,
          episode_list: [%{episode_number: 1, name: "TBA", air_date: nil}]
        })

      create_episode(%{season_id: season.id, episode_number: 1, name: "TBA", cast_person_ids: [7]})
      create_episode(%{season_id: season.id, episode_number: 9, name: "Beyond TMDB"})

      create_title_record(%{
        tmdb_id: 1396,
        media_type: :tv_series,
        payload:
          TmdbStubs.tv_detail(%{
            "id" => 1396,
            "name" => "New Show",
            "status" => "Ended",
            "seasons" => [%{"season_number" => 1}]
          })
      })

      create_season_record(%{
        tmdb_id: 1396,
        season_number: 1,
        payload:
          TmdbStubs.season_detail(%{
            "episodes" => [
              %{
                "episode_number" => 1,
                "name" => "Pilot",
                "air_date" => "2020-01-01",
                "overview" => "It begins.",
                "runtime" => 42
              },
              %{"episode_number" => 2, "name" => "Second", "air_date" => "2020-01-08"}
            ]
          })
      })

      assert :ok = TmdbProjection.reapply({1396, :tv_series})

      {:ok, updated} = Containers.fetch(:tv_series, series.id)
      assert updated.name == "New Show"
      assert updated.status == :ended

      [season] = Library.Seasons.list_for_tv_series(series.id)

      assert Enum.map(season.episode_list, &{&1.episode_number, &1.name}) == [
               {1, "Pilot"},
               {2, "Second"}
             ]

      episodes = season.id |> Library.Episodes.list_for_season() |> Map.new(&{&1.episode_number, &1})
      assert episodes[1].name == "Pilot"
      assert episodes[1].description == "It begins."
      assert episodes[1].date_published == ~D[2020-01-01]
      assert episodes[1].duration_seconds == 2520
      assert episodes[1].cast_person_ids == [7]
      assert episodes[9].name == "Beyond TMDB"

      assert_receive {:entities_changed, %EntitiesChanged{entity_ids: ids}}
      assert series.id in ids
    end

    test "an open season the store lacks is first-contacted; a closed one stays as imported" do
      series = create_tv_series(%{name: "Sample Show", tmdb_id: "1396"})

      create_season(%{
        tv_series_id: series.id,
        season_number: 1,
        episode_list: [%{episode_number: 1, name: "Pilot", air_date: ~D[2020-01-01]}]
      })

      create_season(%{tv_series_id: series.id, season_number: 2, episode_list: []})

      create_title_record(%{
        tmdb_id: 1396,
        media_type: :tv_series,
        payload:
          TmdbStubs.tv_detail(%{
            "id" => 1396,
            "seasons" => [%{"season_number" => 1}, %{"season_number" => 2}]
          })
      })

      TmdbStubs.stub_routes([
        {"/tv/1396/season/2",
         TmdbStubs.season_detail(%{
           "season_number" => 2,
           "episodes" => [%{"episode_number" => 1, "name" => "Return", "air_date" => "2199-01-01"}]
         })},
        {"/tv/1396/season/1", {:error, 500}}
      ])

      assert :ok = TmdbProjection.reapply({1396, :tv_series})

      assert %Store.SeasonRecord{} = Store.get_season(1396, 2)
      assert Store.get_season(1396, 1) == nil

      seasons = series.id |> Library.Seasons.list_for_tv_series() |> Map.new(&{&1.season_number, &1})
      assert Enum.map(seasons[2].episode_list, & &1.name) == ["Return"]
      assert Enum.map(seasons[1].episode_list, & &1.name) == ["Pilot"]
    end
  end
end
