defmodule MediaCentarr.Library.MovieSeriesTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.{MovieSeries, Person}
  alias MediaCentarr.Repo
  alias MediaCentarr.TestFactory

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
               %{name: "Sample Collection", cast: cast_data}
               |> MovieSeries.create_changeset()
               |> Repo.insert()

      reloaded = Repo.get!(MovieSeries, series.id)

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
               %{name: "Sample Collection B"}
               |> MovieSeries.create_changeset()
               |> Repo.insert()

      assert Repo.get!(MovieSeries, series.id).cast == []
    end
  end

  describe "crew field" do
    test "round-trips a list of TMDB-shaped maps as Library.Person structs" do
      crew_data = [
        %{
          "name" => "Director A",
          "job" => "Director",
          "department" => "Directing",
          "tmdb_person_id" => 42,
          "profile_path" => "/d.jpg"
        }
      ]

      assert {:ok, series} =
               %{name: "Sample Collection C", crew: crew_data}
               |> MovieSeries.create_changeset()
               |> Repo.insert()

      reloaded = Repo.get!(MovieSeries, series.id)

      assert [
               %Person{
                 name: "Director A",
                 job: "Director",
                 department: "Directing",
                 tmdb_person_id: 42,
                 profile_path: "/d.jpg"
               }
             ] = reloaded.crew
    end

    test "defaults to [] when not provided" do
      assert {:ok, series} =
               %{name: "Sample Collection D"}
               |> MovieSeries.create_changeset()
               |> Repo.insert()

      assert Repo.get!(MovieSeries, series.id).crew == []
    end
  end

  describe "scalar metadata fields" do
    test "round-trips tagline, original_language, studio, country_code, vote_count, status" do
      attrs = %{
        name: "Sample Collection E",
        tagline: "A grand adventure.",
        original_language: "en",
        studio: "Sample Studio",
        country_code: "US",
        vote_count: 1234,
        status: :released
      }

      assert {:ok, series} =
               attrs
               |> MovieSeries.create_changeset()
               |> Repo.insert()

      reloaded = Repo.get!(MovieSeries, series.id)

      assert reloaded.tagline == "A grand adventure."
      assert reloaded.original_language == "en"
      assert reloaded.studio == "Sample Studio"
      assert reloaded.country_code == "US"
      assert reloaded.vote_count == 1234
      assert reloaded.status == :released
    end

    test "all new scalars default to nil when not provided" do
      assert {:ok, series} =
               %{name: "Sample Collection F"}
               |> MovieSeries.create_changeset()
               |> Repo.insert()

      reloaded = Repo.get!(MovieSeries, series.id)

      assert reloaded.tagline == nil
      assert reloaded.original_language == nil
      assert reloaded.studio == nil
      assert reloaded.country_code == nil
      assert reloaded.vote_count == nil
      assert reloaded.status == nil
    end
  end

  describe "update_credits_changeset/2" do
    test "replaces cast and crew embeds in place" do
      {:ok, series} =
        %{name: "Sample Collection G", cast: [], crew: []}
        |> MovieSeries.create_changeset()
        |> Repo.insert()

      new_cast = [
        %{
          "name" => "New Actor",
          "character" => "New Role",
          "tmdb_person_id" => 7,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      new_crew = [
        %{
          "name" => "New Director",
          "job" => "Director",
          "department" => "Directing",
          "tmdb_person_id" => 9,
          "profile_path" => nil
        }
      ]

      assert {:ok, updated} =
               series
               |> MovieSeries.update_credits_changeset(%{cast: new_cast, crew: new_crew})
               |> Repo.update()

      reloaded = Repo.get!(MovieSeries, updated.id)

      assert [%Person{name: "New Actor"}] = reloaded.cast
      assert [%Person{name: "New Director"}] = reloaded.crew
    end

    test "writing empty lists is allowed (collection payload carries no credits)" do
      {:ok, series} =
        %{name: "Sample Collection H", cast: [], crew: []}
        |> MovieSeries.create_changeset()
        |> Repo.insert()

      assert {:ok, _} =
               series
               |> MovieSeries.update_credits_changeset(%{cast: [], crew: []})
               |> Repo.update()
    end
  end

  describe "update_credits_changeset/2 — no-imdb_id seam" do
    test "casts cast/crew embeds even though MovieSeries has no :imdb_id field" do
      movie_series = TestFactory.create_movie_series()

      attrs = %{
        "cast" => [%{"name" => "Sample Actor"}],
        "crew" => [%{"name" => "Sample Director", "job" => "Director"}]
      }

      {:ok, updated} =
        movie_series
        |> MovieSeries.update_credits_changeset(attrs)
        |> Repo.update()

      assert [%Person{name: "Sample Actor"}] = updated.cast
      assert [%Person{name: "Sample Director", job: "Director"}] = updated.crew
    end
  end
end
