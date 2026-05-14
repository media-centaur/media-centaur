defmodule MediaCentarr.Acquisition.Pursuits.RecipeTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Pursuits.{Pursuit, Recipe}

  describe "from/1 — tmdb movie" do
    test "projects tmdb columns and atomises tmdb_type" do
      pursuit = %Pursuit{
        recipe_type: "tmdb",
        tmdb_type: "movie",
        tmdb_id: "603",
        title: "Sample Movie",
        year: 2010,
        season_number: nil,
        episode_number: nil
      }

      assert %Recipe{
               type: :tmdb,
               tmdb_type: :movie,
               tmdb_id: "603",
               title: "Sample Movie",
               year: 2010,
               season_number: nil,
               episode_number: nil,
               manual_query: nil
             } = Recipe.from(pursuit)
    end
  end

  describe "from/1 — tmdb tv" do
    test "carries season + episode for a per-episode recipe" do
      pursuit = %Pursuit{
        recipe_type: "tmdb",
        tmdb_type: "tv",
        tmdb_id: "1396",
        title: "Sample Show",
        season_number: 1,
        episode_number: 2
      }

      assert %Recipe{
               type: :tmdb,
               tmdb_type: :tv,
               title: "Sample Show",
               season_number: 1,
               episode_number: 2,
               manual_query: nil
             } = Recipe.from(pursuit)
    end

    test "leaves season + episode nil for a series-level recipe" do
      pursuit = %Pursuit{
        recipe_type: "tmdb",
        tmdb_type: "tv",
        tmdb_id: "1396",
        title: "Sample Show",
        season_number: nil,
        episode_number: nil
      }

      assert %Recipe{type: :tmdb, season_number: nil, episode_number: nil} = Recipe.from(pursuit)
    end
  end

  describe "from/1 — prowlarr_query" do
    test "carries manual_query and ignores tmdb columns" do
      pursuit = %Pursuit{
        recipe_type: "prowlarr_query",
        title: "Sample Show S01",
        manual_query: "Sample Show S01E{01,02}",
        tmdb_id: nil,
        tmdb_type: nil
      }

      assert %Recipe{
               type: :prowlarr_query,
               title: "Sample Show S01",
               manual_query: "Sample Show S01E{01,02}",
               tmdb_id: nil,
               tmdb_type: nil
             } = Recipe.from(pursuit)
    end
  end
end
