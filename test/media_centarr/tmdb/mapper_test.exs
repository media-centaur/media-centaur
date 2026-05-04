defmodule MediaCentarr.TMDB.MapperTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.TMDB.Mapper

  describe "movie_attrs/3" do
    test "maps full TMDB movie response to domain attributes" do
      data = %{
        "title" => "Sample Movie",
        "overview" => "A sample movie overview.",
        "release_date" => "2008-07-18",
        "genres" => [%{"name" => "Action"}, %{"name" => "Drama"}],
        "runtime" => 152,
        "vote_average" => 9.0,
        "credits" => %{
          "crew" => [
            %{"department" => "Directing", "job" => "Director", "name" => "Sample Director"}
          ],
          "cast" => [
            %{
              "name" => "Sample Actor",
              "character" => "Sample Role",
              "id" => 99,
              "profile_path" => "/p.jpg",
              "order" => 0
            }
          ]
        },
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" => [%{"certification" => "PG-13"}]
            }
          ]
        }
      }

      result = Mapper.movie_attrs("155", data, "/media/sample_movie.mkv")

      assert result.type == :movie
      assert result.tmdb_id == "155"
      assert result.name == "Sample Movie"
      assert result.description == "A sample movie overview."
      assert result.date_published == "2008-07-18"
      assert result.genres == ["Action", "Drama"]
      assert result.url == "https://www.themoviedb.org/movie/155"
      assert result.duration == "PT2H32M"
      assert result.director == "Sample Director"
      assert result.content_rating == "PG-13"
      assert result.aggregate_rating_value == 9.0
      assert result.content_url == "/media/sample_movie.mkv"

      assert result.cast == [
               %{
                 "name" => "Sample Actor",
                 "character" => "Sample Role",
                 "tmdb_person_id" => 99,
                 "profile_path" => "/p.jpg",
                 "order" => 0
               }
             ]
    end

    test "extracts magazine fields: tagline, original_language, studio, country_code, vote_count" do
      data = %{
        "title" => "Sample Movie B",
        "tagline" => "A Sample Tagline",
        "original_language" => "de",
        "vote_count" => 2341,
        "production_companies" => [
          %{"name" => "Sample Studio"},
          %{"name" => "Other Studio"}
        ],
        "production_countries" => [
          %{"iso_3166_1" => "DE", "name" => "Germany"}
        ]
      }

      result = Mapper.movie_attrs("653", data, nil)

      assert result.tagline == "A Sample Tagline"
      assert result.original_language == "de"
      assert result.studio == "Sample Studio"
      assert result.country_code == "DE"
      assert result.vote_count == 2341
    end

    test "magazine fields are nil when TMDB omits them" do
      data = %{"title" => "Bare Bones"}

      result = Mapper.movie_attrs("1", data, nil)

      assert result.tagline == nil
      assert result.original_language == nil
      assert result.studio == nil
      assert result.country_code == nil
      assert result.vote_count == nil
    end

    test "production_companies / production_countries gracefully handle empty lists" do
      data = %{
        "title" => "Indie",
        "production_companies" => [],
        "production_countries" => []
      }

      result = Mapper.movie_attrs("1", data, nil)

      assert result.studio == nil
      assert result.country_code == nil
    end

    test "nil fields map to nil in result" do
      data = %{
        "title" => "Minimal",
        "overview" => nil,
        "release_date" => nil,
        "genres" => nil,
        "runtime" => nil,
        "vote_average" => nil,
        "credits" => nil,
        "release_dates" => nil,
        "status" => nil
      }

      result = Mapper.movie_attrs("1", data, nil)

      assert result.name == "Minimal"
      assert result.description == nil
      assert result.date_published == nil
      assert result.genres == []
      assert result.duration == nil
      assert result.director == nil
      assert result.content_rating == nil
      assert result.aggregate_rating_value == nil
      assert result.content_url == nil
      assert result.status == nil
    end

    test "maps movie status" do
      data = %{"title" => "Upcoming", "status" => "In Production"}
      result = Mapper.movie_attrs("1", data, nil)
      assert result.status == :in_production
    end

    test "maps released movie status" do
      data = %{"title" => "Old", "status" => "Released"}
      result = Mapper.movie_attrs("1", data, nil)
      assert result.status == :released
    end
  end

  describe "tv_attrs/2" do
    test "maps full TMDB TV response" do
      data = %{
        "name" => "Sample Show",
        "overview" => "A sample show overview.",
        "first_air_date" => "2008-01-20",
        "genres" => [%{"name" => "Drama"}],
        "number_of_seasons" => 5,
        "vote_average" => 8.9,
        "status" => "Ended"
      }

      result = Mapper.tv_attrs("1396", data)

      assert result.type == :tv_series
      assert result.tmdb_id == "1396"
      assert result.name == "Sample Show"
      assert result.description == "A sample show overview."
      assert result.date_published == "2008-01-20"
      assert result.genres == ["Drama"]
      assert result.url == "https://www.themoviedb.org/tv/1396"
      assert result.number_of_seasons == 5
      assert result.aggregate_rating_value == 8.9
      assert result.status == :ended
    end

    test "extracts magazine fields including network" do
      data = %{
        "name" => "Sample Show B",
        "tagline" => "A sample tagline",
        "original_language" => "en",
        "vote_count" => 1502,
        "production_companies" => [%{"name" => "Sample Studio"}],
        "production_countries" => [%{"iso_3166_1" => "US"}],
        "networks" => [%{"name" => "Sample Network"}, %{"name" => "Other Network"}]
      }

      result = Mapper.tv_attrs("1083", data)

      assert result.tagline == "A sample tagline"
      assert result.original_language == "en"
      assert result.studio == "Sample Studio"
      assert result.country_code == "US"
      assert result.vote_count == 1502
      assert result.network == "Sample Network"
    end

    test "TV magazine fields are nil when TMDB omits them" do
      data = %{"name" => "Bare TV"}

      result = Mapper.tv_attrs("1", data)

      assert result.tagline == nil
      assert result.original_language == nil
      assert result.studio == nil
      assert result.country_code == nil
      assert result.vote_count == nil
      assert result.network == nil
    end

    test "maps returning series status" do
      data = %{"name" => "Active Show", "status" => "Returning Series"}
      result = Mapper.tv_attrs("100", data)
      assert result.status == :returning
    end

    test "maps nil status to nil" do
      data = %{"name" => "No Status", "status" => nil}
      result = Mapper.tv_attrs("100", data)
      assert result.status == nil
    end

    test "maps unknown status string to nil" do
      data = %{"name" => "Weird", "status" => "Something New"}
      result = Mapper.tv_attrs("100", data)
      assert result.status == nil
    end
  end

  describe "season_attrs/2" do
    test "extracts season attributes with episode count" do
      season_data = %{
        "season_number" => 2,
        "name" => "Season 2",
        "episodes" => [%{"episode_number" => 1}, %{"episode_number" => 2}]
      }

      result = Mapper.season_attrs("entity-uuid", season_data)

      assert result.entity_id == "entity-uuid"
      assert result.season_number == 2
      assert result.name == "Season 2"
      assert result.number_of_episodes == 2
    end

    test "nil episodes defaults to 0 count" do
      season_data = %{"season_number" => 1, "name" => "Season 1", "episodes" => nil}

      result = Mapper.season_attrs("entity-uuid", season_data)

      assert result.number_of_episodes == 0
    end
  end

  describe "episode_attrs/4" do
    test "finds matching episode by number" do
      season_data = %{
        "episodes" => [
          %{
            "episode_number" => 1,
            "name" => "Pilot",
            "overview" => "The beginning.",
            "runtime" => 58
          },
          %{
            "episode_number" => 2,
            "name" => "Cat's in the Bag...",
            "overview" => "Trouble.",
            "runtime" => 48
          }
        ]
      }

      result = Mapper.episode_attrs("season-uuid", season_data, 2, "/media/S01E02.mkv")

      assert result.season_id == "season-uuid"
      assert result.episode_number == 2
      assert result.name == "Cat's in the Bag..."
      assert result.description == "Trouble."
      assert result.duration == "PT0H48M"
      assert result.content_url == "/media/S01E02.mkv"
    end

    test "missing episode number returns nil fields" do
      season_data = %{"episodes" => [%{"episode_number" => 1, "name" => "Pilot"}]}

      result = Mapper.episode_attrs("season-uuid", season_data, 99, "/media/S01E99.mkv")

      assert result.episode_number == 99
      assert result.name == nil
      assert result.description == nil
      assert result.duration == nil
      assert result.content_url == "/media/S01E99.mkv"
    end
  end

  describe "image_attrs/2" do
    test "builds image attrs from poster, backdrop, and logo paths" do
      data = %{
        "poster_path" => "/poster.jpg",
        "backdrop_path" => "/backdrop.jpg",
        "images" => %{
          "logos" => [%{"iso_639_1" => "en", "file_path" => "/logo.png"}]
        }
      }

      result = Mapper.image_attrs("entity-uuid", data)

      assert length(result) == 3

      poster = Enum.find(result, &(&1.role == "poster"))
      assert poster.entity_id == "entity-uuid"
      assert poster.url == "https://image.tmdb.org/t/p/original/poster.jpg"

      backdrop = Enum.find(result, &(&1.role == "backdrop"))
      assert backdrop.entity_id == "entity-uuid"
      assert backdrop.url == "https://image.tmdb.org/t/p/original/backdrop.jpg"

      logo = Enum.find(result, &(&1.role == "logo"))
      assert logo.entity_id == "entity-uuid"
      assert logo.url == "https://image.tmdb.org/t/p/original/logo.png"
    end

    test "nil paths are skipped" do
      data = %{
        "poster_path" => "/poster.jpg",
        "backdrop_path" => nil,
        "images" => %{"logos" => []}
      }

      result = Mapper.image_attrs("entity-uuid", data)

      assert length(result) == 1
      assert hd(result).role == "poster"
    end
  end

  describe "episode_image_attrs/2" do
    test "still_path present returns thumb image" do
      tmdb_episode = %{"still_path" => "/still.jpg"}

      result = Mapper.episode_image_attrs("episode-uuid", tmdb_episode)

      assert [image] = result
      assert image.episode_id == "episode-uuid"
      assert image.role == "thumb"
      assert image.url == "https://image.tmdb.org/t/p/original/still.jpg"
    end

    test "nil still_path returns empty list" do
      assert Mapper.episode_image_attrs("episode-uuid", %{"still_path" => nil}) == []
    end

    test "nil episode returns empty list" do
      assert Mapper.episode_image_attrs("episode-uuid", nil) == []
    end
  end

  describe "movie_series_attrs/2" do
    test "maps collection data" do
      data = %{
        "name" => "Sample Trilogy",
        "overview" => "Three sample films."
      }

      result = Mapper.movie_series_attrs("263", data)

      assert result.type == :movie_series
      assert result.tmdb_id == "263"
      assert result.name == "Sample Trilogy"
      assert result.description == "Three sample films."
      assert result.url == "https://www.themoviedb.org/collection/263"
    end
  end

  describe "child_movie_attrs/5" do
    test "includes entity_id, tmdb_id as string, and position" do
      data = %{
        "title" => "Sample Origin",
        "overview" => "Origin story.",
        "release_date" => "2005-06-15",
        "runtime" => 140,
        "vote_average" => 7.7,
        "credits" => %{
          "crew" => [
            %{"department" => "Directing", "job" => "Director", "name" => "Sample Director"}
          ]
        },
        "release_dates" => nil
      }

      result = Mapper.child_movie_attrs("entity-uuid", 272, data, "/media/sample_origin.mkv", 0)

      assert result.entity_id == "entity-uuid"
      assert result.tmdb_id == "272"
      assert result.name == "Sample Origin"
      assert result.position == 0
      assert result.content_url == "/media/sample_origin.mkv"
      assert result.director == "Sample Director"
    end
  end

  describe "movie_image_attrs/2" do
    test "uses movie_id key" do
      data = %{"poster_path" => "/poster.jpg", "backdrop_path" => nil}

      result = Mapper.movie_image_attrs("movie-uuid", data)

      assert [image] = result
      assert image.movie_id == "movie-uuid"
      assert image.role == "poster"
    end
  end

  describe "collection_image_attrs/2" do
    test "uses entity_id key" do
      data = %{"poster_path" => "/poster.jpg", "backdrop_path" => nil}

      result = Mapper.collection_image_attrs("entity-uuid", data)

      assert [image] = result
      assert image.entity_id == "entity-uuid"
    end
  end

  describe "tmdb_url/2" do
    test "movie URL" do
      assert Mapper.tmdb_url(:movie, "155") == "https://www.themoviedb.org/movie/155"
    end

    test "tv URL" do
      assert Mapper.tmdb_url(:tv, "1396") == "https://www.themoviedb.org/tv/1396"
    end

    test "collection URL" do
      assert Mapper.tmdb_url(:collection, "263") == "https://www.themoviedb.org/collection/263"
    end
  end

  describe "tmdb_image_url/1" do
    test "nil returns nil" do
      assert Mapper.tmdb_image_url(nil) == nil
    end

    test "path returns full CDN URL" do
      assert Mapper.tmdb_image_url("/abc.jpg") ==
               "https://image.tmdb.org/t/p/original/abc.jpg"
    end
  end

  describe "extract_genre_names/1" do
    test "nil returns empty list" do
      assert Mapper.extract_genre_names(nil) == []
    end

    test "list of genre maps returns names" do
      genres = [%{"name" => "Action"}, %{"name" => "Comedy"}]
      assert Mapper.extract_genre_names(genres) == ["Action", "Comedy"]
    end
  end

  describe "extract_director/1" do
    test "nil returns nil" do
      assert Mapper.extract_director(nil) == nil
    end

    test "crew with Director returns name" do
      credits = %{
        "crew" => [
          %{"department" => "Writing", "job" => "Screenplay", "name" => "Writer"},
          %{"department" => "Directing", "job" => "Director", "name" => "The Director"}
        ]
      }

      assert Mapper.extract_director(credits) == "The Director"
    end

    test "no Director in crew returns nil" do
      credits = %{
        "crew" => [%{"department" => "Writing", "job" => "Screenplay", "name" => "Writer"}]
      }

      assert Mapper.extract_director(credits) == nil
    end
  end

  describe "extract_cast/1" do
    test "extracts cast members ordered by :order ascending" do
      credits = %{
        "cast" => [
          %{
            "name" => "Actor B",
            "character" => "Char B",
            "id" => 2,
            "profile_path" => "/b.jpg",
            "order" => 1
          },
          %{
            "name" => "Actor A",
            "character" => "Char A",
            "id" => 1,
            "profile_path" => "/a.jpg",
            "order" => 0
          },
          %{
            "name" => "Actor C",
            "character" => "Char C",
            "id" => 3,
            "profile_path" => nil,
            "order" => 2
          }
        ]
      }

      assert Mapper.extract_cast(credits) == [
               %{
                 "name" => "Actor A",
                 "character" => "Char A",
                 "tmdb_person_id" => 1,
                 "profile_path" => "/a.jpg",
                 "order" => 0
               },
               %{
                 "name" => "Actor B",
                 "character" => "Char B",
                 "tmdb_person_id" => 2,
                 "profile_path" => "/b.jpg",
                 "order" => 1
               },
               %{
                 "name" => "Actor C",
                 "character" => "Char C",
                 "tmdb_person_id" => 3,
                 "profile_path" => nil,
                 "order" => 2
               }
             ]
    end

    test "returns [] when credits is nil" do
      assert Mapper.extract_cast(nil) == []
    end

    test "returns [] when cast key is missing" do
      assert Mapper.extract_cast(%{"crew" => []}) == []
    end

    test "returns [] when cast is empty list" do
      assert Mapper.extract_cast(%{"cast" => []}) == []
    end
  end

  describe "extract_us_rating/1" do
    test "nil returns nil" do
      assert Mapper.extract_us_rating(nil) == nil
    end

    test "US found returns certification" do
      data = %{
        "results" => [
          %{
            "iso_3166_1" => "US",
            "release_dates" => [%{"certification" => "R"}]
          }
        ]
      }

      assert Mapper.extract_us_rating(data) == "R"
    end

    test "no US entry returns nil" do
      data = %{
        "results" => [
          %{
            "iso_3166_1" => "GB",
            "release_dates" => [%{"certification" => "15"}]
          }
        ]
      }

      assert Mapper.extract_us_rating(data) == nil
    end
  end

  describe "minutes_to_iso8601/1" do
    test "nil returns nil" do
      assert Mapper.minutes_to_iso8601(nil) == nil
    end

    test "90 minutes" do
      assert Mapper.minutes_to_iso8601(90) == "PT1H30M"
    end

    test "120 minutes" do
      assert Mapper.minutes_to_iso8601(120) == "PT2H0M"
    end

    test "45 minutes" do
      assert Mapper.minutes_to_iso8601(45) == "PT0H45M"
    end
  end
end
