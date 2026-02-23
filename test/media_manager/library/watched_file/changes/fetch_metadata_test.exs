defmodule MediaManager.Library.WatchedFile.Changes.FetchMetadataTest do
  use MediaManager.DataCase

  alias MediaManager.Library.Entity
  import MediaManager.TmdbStubs

  setup do
    setup_tmdb_client()
    :ok
  end

  defp create_file_and_fetch(attrs) do
    file = create_approved_file(attrs)

    file
    |> Ash.Changeset.for_update(:fetch_metadata, %{})
    |> Ash.update()
  end

  # ---------------------------------------------------------------------------
  # New entities
  # ---------------------------------------------------------------------------

  describe "new entity creation" do
    test "new movie entity — state = :fetching_images, entity_id set" do
      stub_routes([
        {"/movie/550", movie_detail()}
      ])

      assert {:ok, file} =
               create_file_and_fetch(%{
                 file_path: "/media/fetch/fight_club.mkv",
                 tmdb_id: "550",
                 parsed_type: :movie
               })

      assert file.state == :fetching_images
      assert file.entity_id != nil

      entity = Ash.get!(Entity, file.entity_id)
      assert entity.type == :movie
      assert entity.name == "Fight Club"
    end

    test "new TV entity — state = :fetching_images, entity_id set" do
      stub_routes([
        {"/tv/1396", tv_detail()},
        {"/tv/1396/season/1", season_detail()}
      ])

      assert {:ok, file} =
               create_file_and_fetch(%{
                 file_path: "/media/fetch/bb_s01e01.mkv",
                 tmdb_id: "1396",
                 parsed_type: :tv,
                 season_number: 1,
                 episode_number: 1
               })

      assert file.state == :fetching_images
      assert file.entity_id != nil

      entity = Ash.get!(Entity, file.entity_id)
      assert entity.type == :tv_series
      assert entity.name == "Sample Show Eight"
    end

    test "new movie in collection — state = :fetching_images" do
      stub_routes([
        {"/movie/155", movie_in_collection_detail()},
        {"/collection/263", collection_detail()}
      ])

      assert {:ok, file} =
               create_file_and_fetch(%{
                 file_path: "/media/fetch/dark_knight.mkv",
                 tmdb_id: "155",
                 parsed_type: :movie
               })

      assert file.state == :fetching_images
      entity = Ash.get!(Entity, file.entity_id)
      assert entity.type == :movie_series
    end
  end

  # ---------------------------------------------------------------------------
  # Existing entities
  # ---------------------------------------------------------------------------

  describe "existing entity reuse" do
    test "existing movie — state = :complete (skip images)" do
      existing = create_entity(%{type: :movie, name: "Fight Club"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "550"})

      assert {:ok, file} =
               create_file_and_fetch(%{
                 file_path: "/media/fetch/fight_club_2.mkv",
                 tmdb_id: "550",
                 parsed_type: :movie
               })

      assert file.state == :complete
      assert file.entity_id == existing.id
    end

    test "existing TV — state = :fetching_images (may need new episodes)" do
      existing = create_entity(%{type: :tv_series, name: "Sample Show Eight"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "1396"})

      stub_routes([
        {"/tv/1396/season/2", season_detail(%{"season_number" => 2})}
      ])

      assert {:ok, file} =
               create_file_and_fetch(%{
                 file_path: "/media/fetch/bb_s02e01.mkv",
                 tmdb_id: "1396",
                 parsed_type: :tv,
                 season_number: 2,
                 episode_number: 1
               })

      assert file.state == :fetching_images
      assert file.entity_id == existing.id
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "EntityResolver error — state = :error with message" do
      stub_tmdb_error("/movie/999", 404)

      assert {:ok, file} =
               create_file_and_fetch(%{
                 file_path: "/media/fetch/nonexistent.mkv",
                 tmdb_id: "999",
                 parsed_type: :movie
               })

      assert file.state == :error
      assert file.error_message != nil
    end
  end

  # ---------------------------------------------------------------------------
  # Extra handling
  # ---------------------------------------------------------------------------

  describe "extra resolution" do
    test "extra with parsed_title passed as extra_title in file_context" do
      stub_routes([
        {"/movie/550", movie_detail()}
      ])

      assert {:ok, file} =
               create_file_and_fetch(%{
                 file_path: "/media/fight_club/Extras/making_of.mkv",
                 tmdb_id: "550",
                 parsed_type: :extra,
                 parsed_title: "Making Of"
               })

      assert file.state == :fetching_images
      assert file.entity_id != nil

      entity = Ash.get!(Entity, file.entity_id, action: :with_associations)
      assert entity.type == :movie
      assert length(entity.extras) == 1
      assert hd(entity.extras).name == "Making Of"
    end
  end
end
