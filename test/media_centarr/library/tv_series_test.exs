defmodule MediaCentarr.Library.TVSeriesTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.{Person, TVSeries}
  alias MediaCentarr.Repo

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

      assert {:ok, series} =
               %{name: "Sample Series", cast: cast_data}
               |> TVSeries.create_changeset()
               |> Repo.insert()

      reloaded = Repo.get!(TVSeries, series.id)

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
      assert {:ok, series} =
               %{name: "Sample Series B"}
               |> TVSeries.create_changeset()
               |> Repo.insert()

      assert Repo.get!(TVSeries, series.id).cast == []
    end
  end

  describe "crew field" do
    test "round-trips a list of TMDB-shaped maps as Library.Person structs" do
      crew_data = [
        %{
          "name" => "Showrunner A",
          "job" => "Creator",
          "department" => "Creator",
          "tmdb_person_id" => 42,
          "profile_path" => "/sr.jpg"
        }
      ]

      assert {:ok, series} =
               %{name: "Sample Series D", crew: crew_data}
               |> TVSeries.create_changeset()
               |> Repo.insert()

      reloaded = Repo.get!(TVSeries, series.id)

      assert [
               %Person{
                 name: "Showrunner A",
                 job: "Creator",
                 department: "Creator",
                 tmdb_person_id: 42,
                 profile_path: "/sr.jpg"
               }
             ] = reloaded.crew
    end

    test "defaults to [] when not provided" do
      assert {:ok, series} =
               %{name: "Sample Series E"}
               |> TVSeries.create_changeset()
               |> Repo.insert()

      assert Repo.get!(TVSeries, series.id).crew == []
    end
  end

  describe "imdb_id field" do
    test "round-trips a string" do
      assert {:ok, series} =
               %{name: "Sample Series G", imdb_id: "tt1234567"}
               |> TVSeries.create_changeset()
               |> Repo.insert()

      assert Repo.get!(TVSeries, series.id).imdb_id == "tt1234567"
    end

    test "defaults to nil" do
      assert {:ok, series} =
               %{name: "Sample Series H"}
               |> TVSeries.create_changeset()
               |> Repo.insert()

      assert Repo.get!(TVSeries, series.id).imdb_id == nil
    end
  end
end
