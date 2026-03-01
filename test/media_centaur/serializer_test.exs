defmodule MediaCentaur.SerializerTest do
  use ExUnit.Case, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Config
  alias MediaCentaur.Serializer

  setup do
    original_config = :persistent_term.get({Config, :config})

    tmp_dir = Path.join(System.tmp_dir!(), "serializer_test_#{Ash.UUID.generate()}")
    images_dir = Path.join(tmp_dir, ".media-centaur/images")
    File.mkdir_p!(images_dir)

    config = %{
      watch_dirs: [tmp_dir],
      watch_dir_images: %{tmp_dir => images_dir}
    }

    :persistent_term.put({Config, :config}, config)

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original_config)
      File.rm_rf!(tmp_dir)
    end)

    %{images_dir: images_dir}
  end

  # Creates a fake image file on disk so resolve_image_path/1 finds it.
  defp create_image_file!(images_dir, relative_path) do
    full_path = Path.join(images_dir, relative_path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "fake")
    full_path
  end

  describe "Movie" do
    test "all fields present produces correct JSON-LD structure", %{images_dir: images_dir} do
      entity_id = Ash.UUID.generate()
      expected_path = create_image_file!(images_dir, "#{entity_id}/poster.jpg")

      entity =
        build_entity(%{
          id: entity_id,
          type: :movie,
          name: "Test Movie",
          description: "A test movie.",
          date_published: "2024",
          genres: ["Action", "Drama"],
          director: "Test Director",
          duration: "PT2H",
          content_rating: "R",
          aggregate_rating_value: 8.5,
          url: "https://example.com/movie",
          images: [
            build_image(%{
              role: "poster",
              url: "https://example.com/poster.jpg",
              content_url: "#{entity_id}/poster.jpg"
            })
          ],
          identifiers: [
            build_identifier(%{property_id: "tmdb", value: "12345"})
          ]
        })

      result = Serializer.serialize_entity(entity)

      assert result["@id"] == entity_id

      inner = result["entity"]
      assert inner["@type"] == "Movie"
      assert inner["name"] == "Test Movie"
      assert inner["description"] == "A test movie."
      assert inner["datePublished"] == "2024"
      assert inner["genre"] == ["Action", "Drama"]
      assert inner["director"] == "Test Director"
      assert inner["duration"] == "PT2H"
      assert inner["contentRating"] == "R"
      assert inner["aggregateRating"] == %{"ratingValue" => 8.5}
      assert inner["url"] == "https://example.com/movie"

      [image] = inner["image"]
      assert image["@type"] == "ImageObject"
      assert image["name"] == "poster"
      assert image["url"] == "https://example.com/poster.jpg"
      assert image["contentUrl"] == expected_path

      [identifier] = inner["identifier"]
      assert identifier["@type"] == "PropertyValue"
      assert identifier["propertyID"] == "tmdb"
      assert identifier["value"] == "12345"

      refute Map.has_key?(inner, "numberOfSeasons")
      refute Map.has_key?(inner, "containsSeason")
    end

    test "nil fields and empty lists are omitted via compact" do
      entity = build_entity(%{type: :movie, name: "Minimal"})

      result = Serializer.serialize_entity(entity)
      inner = result["entity"]

      assert inner["@type"] == "Movie"
      assert inner["name"] == "Minimal"

      for key <- [
            "description",
            "datePublished",
            "genre",
            "contentUrl",
            "url",
            "duration",
            "director",
            "contentRating",
            "aggregateRating",
            "identifier"
          ] do
        refute Map.has_key?(inner, key),
               "Expected key #{inspect(key)} to be absent, but it was present"
      end
    end
  end

  describe "TVSeries" do
    test "seasons, episodes, and child movies include @id" do
      episode = build_episode(%{episode_number: 1, name: "Pilot", content_url: "/ep1.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode]})

      entity =
        build_entity(%{
          type: :tv_series,
          name: "ID Test",
          seasons: [season]
        })

      result = Serializer.serialize_entity(entity)
      [serialized_season] = result["entity"]["containsSeason"]
      [serialized_episode] = serialized_season["episode"]

      assert serialized_season["@id"] == season.id
      assert serialized_episode["@id"] == episode.id
    end

    test "seasons sorted by season_number, episodes sorted by episode_number" do
      episode_a = build_episode(%{episode_number: 2, name: "Second"})
      episode_b = build_episode(%{episode_number: 1, name: "First"})
      episode_c = build_episode(%{episode_number: 1, name: "S2 First"})

      season_a = build_season(%{season_number: 2, episodes: [episode_c]})
      season_b = build_season(%{season_number: 1, episodes: [episode_a, episode_b]})

      entity =
        build_entity(%{
          type: :tv_series,
          name: "Test Show",
          number_of_seasons: 2,
          seasons: [season_a, season_b]
        })

      result = Serializer.serialize_entity(entity)
      inner = result["entity"]

      assert inner["@type"] == "TVSeries"
      assert inner["numberOfSeasons"] == 2

      [first_season, second_season] = inner["containsSeason"]
      assert first_season["seasonNumber"] == 1
      assert second_season["seasonNumber"] == 2

      [first_ep, second_ep] = first_season["episode"]
      assert first_ep["episodeNumber"] == 1
      assert first_ep["name"] == "First"
      assert second_ep["episodeNumber"] == 2
      assert second_ep["name"] == "Second"
    end

    test "episode images are serialized", %{images_dir: images_dir} do
      episode_id = Ash.UUID.generate()
      expected_path = create_image_file!(images_dir, "#{episode_id}/thumb.jpg")

      episode =
        build_episode(%{
          id: episode_id,
          episode_number: 1,
          name: "Pilot",
          images: [
            build_image(%{
              role: "thumb",
              url: "https://image.tmdb.org/t/p/original/still.jpg",
              content_url: "#{episode_id}/thumb.jpg"
            })
          ]
        })

      season = build_season(%{season_number: 1, episodes: [episode]})
      entity = build_entity(%{type: :tv_series, name: "Show", seasons: [season]})

      result = Serializer.serialize_entity(entity)

      [serialized_season] = result["entity"]["containsSeason"]
      [serialized_episode] = serialized_season["episode"]

      [image] = serialized_episode["image"]
      assert image["@type"] == "ImageObject"
      assert image["name"] == "thumb"
      assert image["url"] == "https://image.tmdb.org/t/p/original/still.jpg"
      assert image["contentUrl"] == expected_path
    end
  end

  describe "MovieSeries — 1 child" do
    test "exports as @type Movie using child's data", %{images_dir: images_dir} do
      entity_id = Ash.UUID.generate()
      movie_id = Ash.UUID.generate()
      create_image_file!(images_dir, "#{movie_id}/poster.jpg")

      movie =
        build_movie(%{
          id: movie_id,
          name: "First Film",
          description: "A great film.",
          date_published: "2020",
          duration: "PT1H45M",
          director: "Jane Doe",
          content_rating: "PG-13",
          url: "https://example.com/first-film",
          aggregate_rating_value: 7.5,
          tmdb_id: "111",
          position: 0,
          images: [
            build_image(%{
              role: "poster",
              url: "https://example.com/poster.jpg",
              content_url: "#{movie_id}/poster.jpg"
            })
          ]
        })

      entity =
        build_entity(%{
          id: entity_id,
          type: :movie_series,
          name: "Test Collection",
          movies: [movie]
        })

      result = Serializer.serialize_entity(entity)

      assert result["@id"] == entity_id

      inner = result["entity"]
      assert inner["@id"] == movie_id
      assert inner["@type"] == "Movie"
      assert inner["name"] == "First Film"
      assert inner["description"] == "A great film."
      assert inner["duration"] == "PT1H45M"
      assert inner["director"] == "Jane Doe"
      assert inner["contentRating"] == "PG-13"
      assert inner["aggregateRating"] == %{"ratingValue" => 7.5}

      [image] = inner["image"]
      assert image["@type"] == "ImageObject"
      assert image["name"] == "poster"

      [identifier] = inner["identifier"]
      assert identifier["propertyID"] == "tmdb"
      assert identifier["value"] == "111"

      refute Map.has_key?(inner, "hasPart")
    end
  end

  describe "MovieSeries — 2+ children" do
    test "exports as @type MovieSeries with hasPart array, children sorted by position", %{
      images_dir: images_dir
    } do
      entity_id = Ash.UUID.generate()
      expected_series_path = create_image_file!(images_dir, "#{entity_id}/poster.jpg")
      create_image_file!(images_dir, "a/poster.jpg")
      create_image_file!(images_dir, "b/poster.jpg")

      movie_a =
        build_movie(%{
          name: "Part One",
          duration: "PT2H",
          director: "Alice",
          content_rating: "R",
          aggregate_rating_value: 8.0,
          tmdb_id: "201",
          position: 0,
          images: [
            build_image(%{
              role: "poster",
              url: "https://example.com/a-poster.jpg",
              content_url: "a/poster.jpg"
            })
          ]
        })

      movie_b =
        build_movie(%{
          name: "Part Two",
          duration: "PT2H15M",
          director: "Bob",
          content_rating: "R",
          aggregate_rating_value: 7.0,
          tmdb_id: "202",
          position: 1,
          images: [
            build_image(%{
              role: "poster",
              url: "https://example.com/b-poster.jpg",
              content_url: "b/poster.jpg"
            })
          ]
        })

      entity =
        build_entity(%{
          id: entity_id,
          type: :movie_series,
          name: "Test Collection",
          images: [
            build_image(%{
              role: "poster",
              url: "https://example.com/series-poster.jpg",
              content_url: "#{entity_id}/poster.jpg"
            })
          ],
          identifiers: [
            build_identifier(%{property_id: "tmdb_collection", value: "999"})
          ],
          movies: [movie_b, movie_a]
        })

      result = Serializer.serialize_entity(entity)

      assert result["@id"] == entity_id

      inner = result["entity"]
      assert inner["@type"] == "MovieSeries"
      assert inner["name"] == "Test Collection"

      [series_image] = inner["image"]
      assert series_image["@type"] == "ImageObject"
      assert series_image["name"] == "poster"
      assert series_image["contentUrl"] == expected_series_path

      [series_id] = inner["identifier"]
      assert series_id["propertyID"] == "tmdb_collection"
      assert series_id["value"] == "999"

      [first, second] = inner["hasPart"]
      assert first["@id"] == movie_a.id
      assert first["@type"] == "Movie"
      assert first["name"] == "Part One"
      assert first["director"] == "Alice"

      assert first["identifier"] == [
               %{"@type" => "PropertyValue", "propertyID" => "tmdb", "value" => "201"}
             ]

      assert second["@type"] == "Movie"
      assert second["name"] == "Part Two"
      assert second["director"] == "Bob"

      assert second["identifier"] == [
               %{"@type" => "PropertyValue", "propertyID" => "tmdb", "value" => "202"}
             ]

      refute Map.has_key?(inner, "duration")
      refute Map.has_key?(inner, "director")
      refute Map.has_key?(inner, "contentRating")
    end
  end

  describe "Movie with extras" do
    test "extras serialize as hasPart VideoObject entries" do
      entity =
        build_entity(%{
          type: :movie,
          name: "Sample Movie One",
          extras: [
            build_extra(%{name: "Like Home", content_url: "/path/to/Like Home.mkv", position: 0}),
            build_extra(%{name: "Making Of", content_url: "/path/to/Making Of.mkv", position: 1})
          ]
        })

      result = Serializer.serialize_entity(entity)
      inner = result["entity"]

      [first, second] = inner["hasPart"]
      assert first["@id"]
      assert first["@type"] == "VideoObject"
      assert first["name"] == "Like Home"
      assert first["contentUrl"] == "/path/to/Like Home.mkv"
      assert second["@id"]
      assert second["name"] == "Making Of"
    end

    test "movie without extras has no hasPart" do
      entity = build_entity(%{type: :movie, name: "No Extras"})
      result = Serializer.serialize_entity(entity)
      refute Map.has_key?(result["entity"], "hasPart")
    end
  end

  describe "TVSeries with season extras" do
    test "season extras serialize as hasPart on the season object" do
      season_id = Ash.UUID.generate()

      season =
        build_season(%{
          id: season_id,
          season_number: 1,
          episodes: [],
          extras: [
            build_extra(%{
              name: "Behind the Scenes",
              content_url: "/path/to/behind.mkv",
              position: 0,
              season_id: season_id
            }),
            build_extra(%{
              name: "Interview",
              content_url: "/path/to/interview.mkv",
              position: 1,
              season_id: season_id
            })
          ]
        })

      entity =
        build_entity(%{
          type: :tv_series,
          name: "Test Show",
          seasons: [season],
          extras: []
        })

      result = Serializer.serialize_entity(entity)
      [serialized_season] = result["entity"]["containsSeason"]

      [first, second] = serialized_season["hasPart"]
      assert first["@type"] == "VideoObject"
      assert first["name"] == "Behind the Scenes"
      assert first["contentUrl"] == "/path/to/behind.mkv"
      assert second["name"] == "Interview"
    end

    test "season-linked extras do NOT appear in entity-level hasPart" do
      season_id = Ash.UUID.generate()

      season =
        build_season(%{
          id: season_id,
          season_number: 1,
          extras: [
            build_extra(%{
              name: "Featurette",
              content_url: "/path/to/featurette.mkv",
              season_id: season_id
            })
          ]
        })

      entity =
        build_entity(%{
          type: :tv_series,
          name: "Test Show",
          seasons: [season],
          extras: [
            build_extra(%{
              name: "Featurette",
              content_url: "/path/to/featurette.mkv",
              season_id: season_id
            })
          ]
        })

      result = Serializer.serialize_entity(entity)
      inner = result["entity"]

      # Entity-level hasPart should be absent (the only extra has a season_id)
      refute Map.has_key?(inner, "hasPart")

      # Season-level hasPart should have the extra
      [serialized_season] = inner["containsSeason"]
      assert [%{"name" => "Featurette"}] = serialized_season["hasPart"]
    end

    test "entity-level extras and season extras coexist without duplication" do
      season_id = Ash.UUID.generate()

      season =
        build_season(%{
          id: season_id,
          season_number: 1,
          extras: [
            build_extra(%{
              name: "Season Featurette",
              content_url: "/path/to/season-feat.mkv",
              season_id: season_id
            })
          ]
        })

      entity =
        build_entity(%{
          type: :tv_series,
          name: "Test Show",
          seasons: [season],
          extras: [
            build_extra(%{
              name: "Show Overview",
              content_url: "/path/to/overview.mkv",
              season_id: nil
            }),
            build_extra(%{
              name: "Season Featurette",
              content_url: "/path/to/season-feat.mkv",
              season_id: season_id
            })
          ]
        })

      result = Serializer.serialize_entity(entity)
      inner = result["entity"]

      # Entity-level hasPart only contains the non-season extra
      assert [%{"name" => "Show Overview"}] = inner["hasPart"]

      # Season-level hasPart contains the season extra
      [serialized_season] = inner["containsSeason"]
      assert [%{"name" => "Season Featurette"}] = serialized_season["hasPart"]
    end
  end

  describe "images" do
    test "ImageObject with @type, name (role), url, contentUrl", %{images_dir: images_dir} do
      expected_path = create_image_file!(images_dir, "test/backdrop.jpg")

      entity =
        build_entity(%{
          type: :movie,
          name: "Image Test",
          images: [
            build_image(%{
              role: "backdrop",
              url: "https://example.com/backdrop.jpg",
              content_url: "test/backdrop.jpg"
            })
          ]
        })

      result = Serializer.serialize_entity(entity)
      [image] = result["entity"]["image"]

      assert image["@type"] == "ImageObject"
      assert image["name"] == "backdrop"
      assert image["url"] == "https://example.com/backdrop.jpg"
      assert image["contentUrl"] == expected_path
    end
  end

  describe "identifiers" do
    test "PropertyValue with @type, propertyID, value" do
      entity =
        build_entity(%{
          type: :movie,
          name: "ID Test",
          identifiers: [
            build_identifier(%{property_id: "imdb", value: "tt1234567"})
          ]
        })

      result = Serializer.serialize_entity(entity)
      [identifier] = result["entity"]["identifier"]

      assert identifier["@type"] == "PropertyValue"
      assert identifier["propertyID"] == "imdb"
      assert identifier["value"] == "tt1234567"
    end
  end

  describe "compact" do
    test "nil and empty lists removed, 0 and false kept" do
      entity =
        build_entity(%{
          type: :movie,
          name: "Compact Test",
          aggregate_rating_value: 0.0
        })

      result = Serializer.serialize_entity(entity)
      inner = result["entity"]

      assert inner["aggregateRating"] == %{"ratingValue" => 0.0}
      refute Map.has_key?(inner, "description")
      refute Map.has_key?(inner, "genre")
    end
  end
end
