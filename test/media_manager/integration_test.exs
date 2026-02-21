defmodule MediaManager.IntegrationTest do
  use MediaManager.DataCase

  alias MediaManager.Library.{Entity, WatchedFile}

  describe "WatchedFile :detect action" do
    test "creates a record with :detected state and parses file name" do
      assert {:ok, file} =
               WatchedFile
               |> Ash.Changeset.for_create(:detect, %{
                 file_path:
                   "/mnt/videos/Videos/Sample.Movie.Two.1991.BluRay.Remux.1080p.AVC.DTS-HD.MA.5.1-HiFi.mkv"
               })
               |> Ash.create()

      assert file.state == :detected
      assert file.parsed_title == "Sample Movie Two"
      assert file.parsed_year == 1991
      assert file.parsed_type == :movie
    end
  end

  describe "Entity" do
    test "id is a UUID and survives a round-trip read" do
      assert {:ok, entity} =
               Entity
               |> Ash.Changeset.for_create(:create_from_tmdb, %{type: :movie, name: "Round Trip"})
               |> Ash.create()

      assert {:ok, [found]} = Ash.read(Entity)
      assert found.id == entity.id
    end
  end

  describe "Serializer" do
    alias MediaManager.{Serializer}
    alias MediaManager.Library.{Image, Identifier}

    test "movie with associations serializes to DATA-FORMAT.md structure" do
      {:ok, entity} =
        Entity
        |> Ash.Changeset.for_create(:create_from_tmdb, %{
          type: :movie,
          name: "Test Movie",
          description: "A test movie.",
          date_published: "2024",
          genres: ["Action", "Drama"],
          director: "Test Director",
          duration: "PT2H",
          content_rating: "R",
          aggregate_rating_value: 8.5,
          url: "https://example.com/movie"
        })
        |> Ash.create()

      {:ok, _image} =
        Image
        |> Ash.Changeset.for_create(:create, %{
          role: "poster",
          url: "https://example.com/poster.jpg",
          content_url: "images/#{entity.id}/poster.jpg",
          entity_id: entity.id
        })
        |> Ash.create()

      {:ok, _identifier} =
        Identifier
        |> Ash.Changeset.for_create(:create, %{
          property_id: "tmdb",
          value: "12345",
          entity_id: entity.id
        })
        |> Ash.create()

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      result = Serializer.serialize_entity(entity)

      assert result["@id"] == entity.id

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
      assert image["contentUrl"] == "images/#{entity.id}/poster.jpg"

      [identifier] = inner["identifier"]
      assert identifier["@type"] == "PropertyValue"
      assert identifier["propertyID"] == "tmdb"
      assert identifier["value"] == "12345"

      # TVSeries-specific fields should not appear
      refute Map.has_key?(inner, "numberOfSeasons")
      refute Map.has_key?(inner, "containsSeason")
    end

    test "nil fields and empty lists are omitted from output" do
      {:ok, entity} =
        Entity
        |> Ash.Changeset.for_create(:create_from_tmdb, %{type: :movie, name: "Minimal"})
        |> Ash.create()

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
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

  describe "Serializer — MovieSeries" do
    alias MediaManager.{Serializer}
    alias MediaManager.Library.{Image, Identifier, Movie}

    test "movie_series with 1 child exports as Movie using child's data" do
      {:ok, entity} =
        Entity
        |> Ash.Changeset.for_create(:create_from_tmdb, %{
          type: :movie_series,
          name: "Test Collection"
        })
        |> Ash.create()

      {:ok, movie} =
        Movie
        |> Ash.Changeset.for_create(:create, %{
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
          entity_id: entity.id
        })
        |> Ash.create()

      {:ok, _image} =
        Image
        |> Ash.Changeset.for_create(:create, %{
          role: "poster",
          url: "https://example.com/poster.jpg",
          content_url: "images/#{movie.id}/poster.jpg",
          movie_id: movie.id
        })
        |> Ash.create()

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      result = Serializer.serialize_entity(entity)

      assert result["@id"] == entity.id

      inner = result["entity"]
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

    test "movie_series with 2+ children exports as MovieSeries with hasPart" do
      {:ok, entity} =
        Entity
        |> Ash.Changeset.for_create(:create_from_tmdb, %{
          type: :movie_series,
          name: "Test Collection"
        })
        |> Ash.create()

      {:ok, _series_image} =
        Image
        |> Ash.Changeset.for_create(:create, %{
          role: "poster",
          url: "https://example.com/series-poster.jpg",
          content_url: "images/#{entity.id}/poster.jpg",
          entity_id: entity.id
        })
        |> Ash.create()

      {:ok, _series_identifier} =
        Identifier
        |> Ash.Changeset.for_create(:create, %{
          property_id: "tmdb_collection",
          value: "999",
          entity_id: entity.id
        })
        |> Ash.create()

      {:ok, movie_a} =
        Movie
        |> Ash.Changeset.for_create(:create, %{
          name: "Part One",
          duration: "PT2H",
          director: "Alice",
          content_rating: "R",
          aggregate_rating_value: 8.0,
          tmdb_id: "201",
          position: 0,
          entity_id: entity.id
        })
        |> Ash.create()

      {:ok, _img_a} =
        Image
        |> Ash.Changeset.for_create(:create, %{
          role: "poster",
          url: "https://example.com/a-poster.jpg",
          content_url: "images/#{movie_a.id}/poster.jpg",
          movie_id: movie_a.id
        })
        |> Ash.create()

      {:ok, movie_b} =
        Movie
        |> Ash.Changeset.for_create(:create, %{
          name: "Part Two",
          duration: "PT2H15M",
          director: "Bob",
          content_rating: "R",
          aggregate_rating_value: 7.0,
          tmdb_id: "202",
          position: 1,
          entity_id: entity.id
        })
        |> Ash.create()

      {:ok, _img_b} =
        Image
        |> Ash.Changeset.for_create(:create, %{
          role: "poster",
          url: "https://example.com/b-poster.jpg",
          content_url: "images/#{movie_b.id}/poster.jpg",
          movie_id: movie_b.id
        })
        |> Ash.create()

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      result = Serializer.serialize_entity(entity)

      assert result["@id"] == entity.id

      inner = result["entity"]
      assert inner["@type"] == "MovieSeries"
      assert inner["name"] == "Test Collection"

      [series_image] = inner["image"]
      assert series_image["@type"] == "ImageObject"
      assert series_image["name"] == "poster"
      assert series_image["contentUrl"] == "images/#{entity.id}/poster.jpg"

      [series_id] = inner["identifier"]
      assert series_id["propertyID"] == "tmdb_collection"
      assert series_id["value"] == "999"

      children = inner["hasPart"]
      assert length(children) == 2

      [first, second] = children
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

      # Series-level should not have movie-specific fields
      refute Map.has_key?(inner, "duration")
      refute Map.has_key?(inner, "director")
      refute Map.has_key?(inner, "contentRating")
    end
  end

  describe "JsonWriter.regenerate_all/1" do
    test "writes a valid JSON array to the given path" do
      json_path = Path.join(System.tmp_dir!(), "media.json")

      assert :ok = MediaManager.JsonWriter.regenerate_all(json_path)

      assert {:ok, contents} = File.read(json_path)
      assert {:ok, entries} = Jason.decode(contents)
      assert is_list(entries)
    end
  end

  @tag :external
  test "WatchedFile :search finds The Shadowy Sentinel with high confidence" do
    {:ok, file} =
      WatchedFile
      |> Ash.Changeset.for_create(:detect, %{
        file_path: "/media/The.Shadowy.Sentinel.2008.1080p.BluRay.mkv"
      })
      |> Ash.create()

    {:ok, file} =
      file
      |> Ash.Changeset.for_update(:search, %{})
      |> Ash.update()

    assert file.state in [:approved, :pending_review],
           "Expected :approved or :pending_review, got :#{file.state}. Error: #{file.error_message}"

    assert file.tmdb_id == "155"
    assert file.confidence_score >= 0.85
  end

  @tag :external
  test "WatchedFile :fetch_metadata creates entity with images" do
    {:ok, file} =
      WatchedFile
      |> Ash.Changeset.for_create(:detect, %{
        file_path: "/media/fetch_meta/The.Shadowy.Sentinel.2008.1080p.BluRay.mkv"
      })
      |> Ash.create()

    {:ok, file} =
      file
      |> Ash.Changeset.for_update(:search, %{})
      |> Ash.update()

    assert file.state in [:approved, :pending_review],
           "Search failed: #{file.error_message}"

    {:ok, file} =
      file
      |> Ash.Changeset.for_update(:fetch_metadata, %{})
      |> Ash.update()

    assert file.state == :fetching_images,
           "Expected :fetching_images, got :#{file.state}. Error: #{file.error_message}"

    assert file.entity_id != nil

    entity = Ash.get!(Entity, file.entity_id, action: :with_associations)
    assert entity.name == "The Shadowy Sentinel"
    assert entity.type == :movie
    assert length(entity.images) >= 1
    assert Enum.any?(entity.images, &(&1.role == "poster"))
  end
end
