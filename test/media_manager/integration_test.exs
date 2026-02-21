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
