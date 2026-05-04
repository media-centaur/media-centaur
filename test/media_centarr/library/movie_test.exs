defmodule MediaCentarr.Library.MovieTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.Movie
  alias MediaCentarr.Repo

  describe "cast field" do
    test "round-trips a list-of-maps through SQLite" do
      cast_data = [
        %{
          "name" => "Actor A",
          "character" => "Role A",
          "tmdb_person_id" => 1,
          "profile_path" => "/a.jpg",
          "order" => 0
        }
      ]

      assert {:ok, movie} =
               %{name: "Sample Movie", cast: cast_data}
               |> Movie.create_changeset()
               |> Repo.insert()

      reloaded = Repo.get!(Movie, movie.id)
      assert reloaded.cast == cast_data
    end

    test "defaults to [] when not provided" do
      assert {:ok, movie} =
               %{name: "Sample Movie B"}
               |> Movie.create_changeset()
               |> Repo.insert()

      assert Repo.get!(Movie, movie.id).cast == []
    end

    test "coerces nil cast to []" do
      assert {:ok, movie} =
               %{name: "Sample Movie C", cast: nil}
               |> Movie.create_changeset()
               |> Repo.insert()

      assert Repo.get!(Movie, movie.id).cast == []
    end
  end
end
