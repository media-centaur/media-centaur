defmodule MediaManager.Library.WatchedFileTest do
  use MediaManager.DataCase

  alias MediaManager.Library.WatchedFile

  describe "WatchedFile :detect action" do
    test "creates a record with :detected state and parses file name" do
      assert {:ok, file} =
               WatchedFile
               |> Ash.Changeset.for_create(:detect, %{
                 file_path:
                   "/mnt/videos/Videos/Sample.Title.Fy.1991.BluRay.Remux.1080p.AVC.DTS-HD.MA.5.1-HiFi.mkv"
               })
               |> Ash.create()

      assert file.state == :detected
      assert file.parsed_title == "Sample Title Fy"
      assert file.parsed_year == 1991
      assert file.parsed_type == :movie
    end

    test "stores watch_dir when provided" do
      assert {:ok, file} =
               WatchedFile
               |> Ash.Changeset.for_create(:detect, %{
                 file_path: "/media/movies/Sample Title Fx.2010.mkv",
                 watch_dir: "/media/movies"
               })
               |> Ash.create()

      assert file.watch_dir == "/media/movies"
    end
  end

  @tag :external
  test "WatchedFile :search finds Sample Title Cx with high confidence" do
    {:ok, file} =
      WatchedFile
      |> Ash.Changeset.for_create(:detect, %{
        file_path: "/media/Sample.Title.Cx.2008.1080p.BluRay.mkv"
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
        file_path: "/media/fetch_meta/Sample.Title.Cx.2008.1080p.BluRay.mkv"
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

    # Sample Title Cx belongs to a TMDB collection, so the entity is a MovieSeries
    # with the collection name. The movie itself is a child record.
    assert entity.type == :movie_series
    assert entity.name == "Sample Title Cx Collection"
    assert length(entity.images) >= 1
    assert Enum.any?(entity.images, &(&1.role == "poster"))

    assert length(entity.movies) >= 1
    dark_knight = Enum.find(entity.movies, &(&1.name == "Sample Title Cx"))
    assert dark_knight != nil
  end
end
