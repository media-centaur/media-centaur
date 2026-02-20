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
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()

      assert {:ok, [found]} = Ash.read(Entity)
      assert found.id == entity.id
    end
  end

  describe "JsonWriter.regenerate_all/0" do
    test "writes a valid JSON array to the output dir" do
      output_dir = System.tmp_dir!()

      assert :ok = MediaManager.JsonWriter.regenerate_all(output_dir)

      json_path = Path.join(output_dir, "media.json")
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
