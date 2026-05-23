defmodule MediaCentaur.Library.MovieTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.{Movie, Person}
  alias MediaCentaur.Repo

  describe "cast field" do
    test "round-trips a list of TMDB-shaped maps as Library.Person structs" do
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

      assert [
               %Person{
                 name: "Actor A",
                 character: "Role A",
                 tmdb_person_id: 1,
                 profile_path: "/a.jpg",
                 order: 0
               }
             ] = reloaded.cast
    end

    test "defaults to [] when not provided" do
      assert {:ok, movie} =
               %{name: "Sample Movie B"}
               |> Movie.create_changeset()
               |> Repo.insert()

      assert Repo.get!(Movie, movie.id).cast == []
    end
  end
end
