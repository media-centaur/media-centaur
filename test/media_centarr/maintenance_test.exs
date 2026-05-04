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

  describe "refresh_movie_cast/0" do
    setup [:setup_tmdb_client]

    test "populates cast on movies with empty cast and a tmdb_id" do
      {:ok, movie} =
        %{name: "Sample Movie", tmdb_id: "123", cast: []}
        |> Movie.create_changeset()
        |> Repo.insert()

      stub_get_movie("123", %{
        "credits" => %{
          "cast" => [
            %{
              "name" => "Sample Actor",
              "character" => "Sample Role",
              "id" => 7,
              "profile_path" => "/p.jpg",
              "order" => 0
            }
          ]
        }
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_movie_cast()

      reloaded = Repo.get!(Movie, movie.id)

      assert reloaded.cast == [
               %{
                 "name" => "Sample Actor",
                 "character" => "Sample Role",
                 "tmdb_person_id" => 7,
                 "profile_path" => "/p.jpg",
                 "order" => 0
               }
             ]
    end

    test "skips movies that already have non-empty cast" do
      existing_cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      {:ok, _} =
        %{name: "Sample Movie", tmdb_id: "456", cast: existing_cast}
        |> Movie.create_changeset()
        |> Repo.insert()

      assert {:ok, %{updated: 0, skipped: 1, failed: 0}} = Maintenance.refresh_movie_cast()
    end

    test "skips movies without a tmdb_id" do
      {:ok, _} =
        %{name: "Sample Movie", tmdb_id: nil, cast: []}
        |> Movie.create_changeset()
        |> Repo.insert()

      assert {:ok, %{updated: 0, skipped: 0, failed: 0}} = Maintenance.refresh_movie_cast()
    end
  end
end
