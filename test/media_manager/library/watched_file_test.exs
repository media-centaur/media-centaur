defmodule MediaManager.Library.WatchedFileTest do
  use MediaManager.DataCase

  alias MediaManager.Library.WatchedFile

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

    test "stores watch_dir when provided" do
      assert {:ok, file} =
               WatchedFile
               |> Ash.Changeset.for_create(:detect, %{
                 file_path: "/media/movies/Inception.2010.mkv",
                 watch_dir: "/media/movies"
               })
               |> Ash.create()

      assert file.watch_dir == "/media/movies"
    end
  end

  describe "WatchedFile :link_file action" do
    test "creates record with entity_id and state :complete" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})

      assert {:ok, file} =
               WatchedFile
               |> Ash.Changeset.for_create(:link_file, %{
                 file_path: "/media/test/linked.mkv",
                 watch_dir: "/media/test",
                 entity_id: entity.id
               })
               |> Ash.create()

      assert file.state == :complete
      assert file.entity_id == entity.id
      assert file.file_path == "/media/test/linked.mkv"
      assert file.watch_dir == "/media/test"
    end

    test "upserts on duplicate file_path" do
      entity1 = create_entity(%{type: :movie, name: "First Movie"})
      entity2 = create_entity(%{type: :movie, name: "Second Movie"})

      {:ok, first} =
        WatchedFile
        |> Ash.Changeset.for_create(:link_file, %{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          entity_id: entity1.id
        })
        |> Ash.create()

      {:ok, second} =
        WatchedFile
        |> Ash.Changeset.for_create(:link_file, %{
          file_path: "/media/test/same.mkv",
          watch_dir: "/media/test",
          entity_id: entity2.id
        })
        |> Ash.create()

      assert first.id == second.id
      assert second.state == :complete

      # Only one record exists
      all = Ash.read!(WatchedFile)
      assert length(all) == 1
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

    entity = Ash.get!(MediaManager.Library.Entity, file.entity_id, action: :with_associations)

    # The Shadowy Sentinel belongs to a TMDB collection, so the entity is a MovieSeries
    # with the collection name. The movie itself is a child record.
    assert entity.type == :movie_series
    assert entity.name == "The Shadowy Sentinel Collection"
    assert length(entity.images) >= 1
    assert Enum.any?(entity.images, &(&1.role == "poster"))

    assert length(entity.movies) >= 1
    dark_knight = Enum.find(entity.movies, &(&1.name == "The Shadowy Sentinel"))
    assert dark_knight != nil
  end
end
