defmodule MediaCentaurWeb.Components.Detail.TitlePreviewTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.Components.Detail.TitlePreview

  test "movie/3 builds a detail-shaped preview from a full TMDB payload" do
    tmdb_movie = %{
      "id" => 550,
      "title" => "Sample Movie",
      "imdb_id" => "tt0137523",
      "tagline" => "Every confirmation counts.",
      "release_date" => "1999-10-15",
      "overview" => "A sample movie overview.",
      "runtime" => 139,
      "genres" => [%{"id" => 18, "name" => "Drama"}, %{"id" => 80, "name" => "Crime"}],
      "vote_average" => 8.4,
      "vote_count" => 26_000,
      "original_language" => "en",
      "production_companies" => [%{"name" => "Sample Studio"}],
      "production_countries" => [%{"iso_3166_1" => "US"}],
      "status" => "Released",
      "poster_path" => "/poster.jpg",
      "backdrop_path" => "/backdrop.jpg",
      "images" => %{"logos" => [%{"iso_639_1" => "en", "file_path" => "/logo.png"}]},
      "release_dates" => %{
        "results" => [
          %{"iso_3166_1" => "US", "release_dates" => [%{"certification" => "R"}]}
        ]
      },
      "credits" => %{
        "cast" => [
          %{
            "name" => "Actor One",
            "character" => "The Narrator",
            "id" => 1,
            "profile_path" => "/a1.jpg",
            "order" => 0
          },
          %{
            "name" => "Actor Two",
            "character" => "Tyler",
            "id" => 2,
            "profile_path" => nil,
            "order" => 1
          }
        ],
        "crew" => [%{"name" => "Jane Director", "job" => "Director", "department" => "Directing"}]
      }
    }

    preview = TitlePreview.movie(tmdb_movie, false)

    assert %TitlePreview{media_type: :movie} = preview
    assert preview.tmdb_id == "550"
    # Carried so the plan the confirm stage creates knows the film's
    # identity the way indexers spell it.
    assert preview.imdb_id == "tt0137523"
    assert preview.title == "Sample Movie"
    assert preview.tagline == "Every confirmation counts."
    assert preview.overview == "A sample movie overview."
    assert preview.in_library? == false

    assert preview.backdrop_url == "https://image.tmdb.org/t/p/original/backdrop.jpg"
    assert preview.logo_url == "https://image.tmdb.org/t/p/original/logo.png"
    assert preview.poster_url == "https://image.tmdb.org/t/p/original/poster.jpg"

    # Metadata row items (facet-strip fields intentionally excluded here).
    assert "1999" in preview.metadata_items
    assert "2h 19m" in preview.metadata_items
    assert "R" in preview.metadata_items
    assert "US" in preview.metadata_items

    director = Enum.find(preview.facets, &(&1.label == "Director"))
    assert director.value == "Jane Director"

    rating = Enum.find(preview.facets, &(&1.label == "Rating"))
    assert rating.value.rating == 8.4

    genres = Enum.find(preview.facets, &(&1.label == "Genres"))
    assert genres.value == ["Drama", "Crime"]

    assert [%Person{name: "Actor One", character: "The Narrator"}, %Person{name: "Actor Two"}] =
             preview.cast
  end

  test "movie/3 carries the canonical release year for the download query" do
    # Later theatrical release_date, earlier digital typed date — the plan
    # query must use the year indexers actually tag (the digital 2025), not
    # the primary theatrical 2026.
    tmdb_movie = %{
      "id" => 1_422_011,
      "title" => "Sample Movie",
      "release_date" => "2026-08-21",
      "release_dates" => %{
        "results" => [
          %{
            "iso_3166_1" => "US",
            "release_dates" => [
              %{"type" => 3, "release_date" => "2026-08-21T00:00:00.000Z"},
              %{"type" => 4, "release_date" => "2025-12-10T00:00:00.000Z"}
            ]
          }
        ]
      }
    }

    preview = TitlePreview.movie(tmdb_movie, false)

    assert preview.year == 2025
    assert "2025" in preview.metadata_items
  end

  test "movie/3 marks a movie whose earliest typed release is still ahead as upcoming" do
    tmdb_movie = %{
      "id" => 1_422_011,
      "title" => "Sample Movie",
      "release_date" => "2027-03-05",
      "release_dates" => %{
        "results" => [
          %{
            "iso_3166_1" => "US",
            "release_dates" => [%{"type" => 3, "release_date" => "2027-03-05T00:00:00.000Z"}]
          }
        ]
      }
    }

    assert TitlePreview.movie(tmdb_movie, false, ~D[2026-08-06]).upcoming?
  end

  test "movie/3 marks a released movie as not upcoming" do
    tmdb_movie = %{
      "id" => 550,
      "title" => "Sample Movie",
      "release_date" => "2016-03-18",
      "release_dates" => %{
        "results" => [
          %{
            "iso_3166_1" => "US",
            "release_dates" => [%{"type" => 3, "release_date" => "2016-03-18T00:00:00.000Z"}]
          }
        ]
      }
    }

    refute TitlePreview.movie(tmdb_movie, false, ~D[2026-08-06]).upcoming?

    # Out today counts as out.
    refute TitlePreview.movie(tmdb_movie, false, ~D[2016-03-18]).upcoming?
  end

  test "movie/3 treats an undated movie as upcoming" do
    tmdb_movie = %{"id" => 550, "title" => "Sample Movie"}

    assert TitlePreview.movie(tmdb_movie, false, ~D[2026-08-06]).upcoming?
  end

  test "movie/3 tolerates a sparse TMDB payload" do
    tmdb_movie = %{"id" => 550, "title" => "Sample Movie", "overview" => ""}

    preview = TitlePreview.movie(tmdb_movie, true)

    assert %TitlePreview{media_type: :movie} = preview
    assert preview.tmdb_id == "550"
    assert preview.imdb_id == nil
    assert preview.title == "Sample Movie"
    assert preview.year == nil
    assert preview.overview == nil
    assert preview.tagline == nil
    assert preview.in_library? == true

    assert preview.backdrop_url == nil
    assert preview.logo_url == nil
    assert preview.poster_url == nil

    assert preview.metadata_items == []
    assert preview.facets == []
    assert preview.cast == []
  end

  test "tv/3 builds a series preview: first-air year, season count, network facet, top cast" do
    tmdb_show = %{
      "id" => 1396,
      "name" => "Sample Show",
      "tagline" => "Every season counts.",
      "first_air_date" => "2008-01-20",
      "overview" => "A sample show overview.",
      "number_of_seasons" => 5,
      "genres" => [%{"id" => 18, "name" => "Drama"}],
      "vote_average" => 8.9,
      "vote_count" => 12_000,
      "original_language" => "en",
      "networks" => [%{"name" => "Sample Network"}],
      "production_countries" => [%{"iso_3166_1" => "US"}],
      "poster_path" => "/poster.jpg",
      "backdrop_path" => "/backdrop.jpg",
      "images" => %{"logos" => [%{"iso_639_1" => "en", "file_path" => "/logo.png"}]},
      "aggregate_credits" => %{
        "cast" => [
          %{
            "name" => "Actor One",
            "id" => 1,
            "profile_path" => "/a1.jpg",
            "order" => 0,
            "roles" => [%{"character" => "Lead"}]
          }
        ]
      }
    }

    preview = TitlePreview.tv(tmdb_show, false, ~D[2026-09-05])

    assert %TitlePreview{media_type: :tv_series, tmdb_id: "1396", title: "Sample Show"} = preview
    assert preview.tagline == "Every season counts."
    assert preview.year == 2008
    assert preview.backdrop_url == "https://image.tmdb.org/t/p/original/backdrop.jpg"
    assert preview.logo_url == "https://image.tmdb.org/t/p/original/logo.png"
    assert "2008" in preview.metadata_items
    assert "5 seasons" in preview.metadata_items
    assert "US" in preview.metadata_items
    assert Enum.find(preview.facets, &(&1.label == "Network")).value == "Sample Network"
    assert [%Person{name: "Actor One"}] = preview.cast
    refute preview.upcoming?
    assert TitlePreview.badge_text(preview) == "TV series"
  end

  test "tv/3 marks an unaired or undated series as upcoming" do
    assert TitlePreview.tv(
             %{"id" => 1, "name" => "Sample Show", "first_air_date" => "2999-01-01"},
             false
           ).upcoming?

    assert TitlePreview.tv(%{"id" => 1, "name" => "Sample Show"}, false).upcoming?
  end
end
