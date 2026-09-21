defmodule MediaCentaur.Showcase.CatalogMatchTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Showcase.CatalogMatch

  defp result(id, title, date), do: %{"id" => id, "title" => title, "release_date" => date}

  describe "pick/4" do
    test "refuses a popular near-miss and names what it saw" do
      # The catalog asks for the Blender short "Spring" (2019); TMDB ranks
      # "Spring Breakers" (2013) first because it is the better-known film.
      # Taking the top hit put a copyrighted title in the showcase catalog
      # and then in a marketing screenshot.
      results = [
        result(97_020, "Spring Breakers", "2013-03-06"),
        result(552_332, "Spring", "2019-04-10")
      ]

      assert {:ok, 552_332} = CatalogMatch.pick(results, "Spring", 2019, "title")
    end

    test "no title match at all is an error, not a guess" do
      results = [result(97_020, "Spring Breakers", "2013-03-06")]

      assert {:error, {:no_match, seen}} = CatalogMatch.pick(results, "Spring", 2019, "title")
      assert "Spring Breakers (2013)" in seen
    end

    test "an empty result list is an error" do
      assert {:error, {:no_match, []}} = CatalogMatch.pick([], "Spring", 2019, "title")
    end

    test "matching ignores case, punctuation and accents" do
      results = [result(1, "The Cabinet of Dr. Caligari", "1920-02-27")]

      assert {:ok, 1} = CatalogMatch.pick(results, "the cabinet of dr caligari", 1920, "title")
    end

    test "a year one off still matches — release dates drift by region" do
      results = [result(1, "Sprite Fright", "2021-10-29")]

      assert {:ok, 1} = CatalogMatch.pick(results, "Sprite Fright", 2022, "title")
    end

    test "the same title from the wrong decade is rejected" do
      results = [result(1, "Nosferatu", "2024-12-25")]

      assert {:error, {:no_match, _seen}} = CatalogMatch.pick(results, "Nosferatu", 1922, "title")
    end

    test "the closest year wins when a title was remade" do
      results = [
        result(1, "Nosferatu", "2024-12-25"),
        result(2, "Nosferatu", "1922-02-16")
      ]

      assert {:ok, 2} = CatalogMatch.pick(results, "Nosferatu", 1922, "title")
    end

    test "an original title counts as a match" do
      results = [
        %{
          "id" => 7,
          "title" => "Man with a Movie Camera",
          "original_title" => "Chelovek s kinoapparatom",
          "release_date" => "1929-01-08"
        }
      ]

      assert {:ok, 7} = CatalogMatch.pick(results, "Chelovek s kinoapparatom", 1929, "title")
    end

    test "TV results are keyed on name" do
      results = [%{"id" => 3, "name" => "Sample Show", "first_air_date" => "1962-09-26"}]

      assert {:ok, 3} = CatalogMatch.pick(results, "Sample Show", 1962, "name")
    end
  end
end
