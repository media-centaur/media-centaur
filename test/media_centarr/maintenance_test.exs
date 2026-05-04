defmodule MediaCentarr.MaintenanceTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.Movie
  alias MediaCentarr.Maintenance
  alias MediaCentarr.Repo
  alias MediaCentarr.Review

  import MediaCentarr.TestFactory
  import MediaCentarr.TmdbStubs

  describe "clear_database/0" do
    test "destroys pending review files" do
      create_pending_file()
      create_pending_file()

      assert [_, _] = Review.list_pending_files()

      Maintenance.clear_database()

      assert [] = Review.list_pending_files()
    end
  end

  describe "refresh_movie_credits/0" do
    setup [:setup_tmdb_client]

    test "populates cast, crew, and imdb_id on movies with empty credits and a tmdb_id" do
      {:ok, movie} =
        %{name: "Sample Movie", tmdb_id: "123", cast: [], crew: []}
        |> Movie.create_changeset()
        |> Repo.insert()

      stub_get_movie("123", %{
        "imdb_id" => "tt0000123",
        "credits" => %{
          "cast" => [
            %{
              "name" => "Sample Actor",
              "character" => "Sample Role",
              "id" => 7,
              "profile_path" => "/p.jpg",
              "order" => 0
            }
          ],
          "crew" => [
            %{
              "id" => 9,
              "name" => "Sample Director",
              "department" => "Directing",
              "job" => "Director",
              "profile_path" => "/d.jpg"
            }
          ]
        }
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_movie_credits()

      reloaded = Repo.get!(Movie, movie.id)

      assert reloaded.imdb_id == "tt0000123"

      assert reloaded.cast == [
               %{
                 "name" => "Sample Actor",
                 "character" => "Sample Role",
                 "tmdb_person_id" => 7,
                 "profile_path" => "/p.jpg",
                 "order" => 0
               }
             ]

      assert reloaded.crew == [
               %{
                 "tmdb_person_id" => 9,
                 "name" => "Sample Director",
                 "job" => "Director",
                 "department" => "Directing",
                 "profile_path" => "/d.jpg"
               }
             ]
    end

    test "skips movies that already have non-empty cast and crew" do
      existing_cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      existing_crew = [
        %{
          "tmdb_person_id" => 2,
          "name" => "Existing Director",
          "job" => "Director",
          "department" => "Directing",
          "profile_path" => nil
        }
      ]

      {:ok, _} =
        %{name: "Sample Movie", tmdb_id: "456", cast: existing_cast, crew: existing_crew}
        |> Movie.create_changeset()
        |> Repo.insert()

      assert {:ok, %{updated: 0, skipped: 1, failed: 0}} = Maintenance.refresh_movie_credits()
    end

    test "refetches a movie that has cast but no crew" do
      cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      {:ok, _} =
        %{name: "Sample Movie", tmdb_id: "789", cast: cast, crew: []}
        |> Movie.create_changeset()
        |> Repo.insert()

      stub_get_movie("789", %{
        "imdb_id" => "tt0000789",
        "credits" => %{
          "cast" => cast,
          "crew" => [
            %{
              "id" => 9,
              "name" => "Sample Director",
              "department" => "Directing",
              "job" => "Director",
              "profile_path" => nil
            }
          ]
        }
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_movie_credits()
    end

    test "skips movies without a tmdb_id" do
      {:ok, _} =
        %{name: "Sample Movie", tmdb_id: nil, cast: [], crew: []}
        |> Movie.create_changeset()
        |> Repo.insert()

      assert {:ok, %{updated: 0, skipped: 0, failed: 0}} = Maintenance.refresh_movie_credits()
    end
  end
end
