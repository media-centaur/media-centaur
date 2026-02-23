defmodule MediaManager.PipelineTest do
  @moduledoc """
  End-to-end pipeline flow tests. Calls `Pipeline.process_file/1` logic
  directly (without Broadway) to verify the full search → fetch → download
  lifecycle.
  """
  use MediaManager.DataCase

  alias MediaManager.Library.{Entity, WatchedFile}
  import MediaManager.TmdbStubs

  setup do
    setup_tmdb_client()
    :ok
  end

  # We replicate Pipeline.process_file/1 logic here since it's private.
  # This tests the same sequence: search → maybe_fetch_metadata → maybe_download_images
  defp process_file(file) do
    with {:ok, searched} <- search(file),
         {:ok, fetched} <- maybe_fetch_metadata(searched),
         {:ok, downloaded} <- maybe_download_images(fetched) do
      {:ok, downloaded}
    end
  end

  defp search(file) do
    Ash.update(file, %{}, action: :search)
  end

  defp maybe_fetch_metadata(%WatchedFile{state: :approved} = file) do
    Ash.update(file, %{}, action: :fetch_metadata)
  end

  defp maybe_fetch_metadata(file), do: {:ok, file}

  defp maybe_download_images(%WatchedFile{state: :fetching_images} = file) do
    case Ash.update(file, %{}, action: :download_images) do
      {:ok, downloaded} -> {:ok, downloaded}
      {:error, _} -> {:ok, file}
    end
  end

  defp maybe_download_images(file), do: {:ok, file}

  # ---------------------------------------------------------------------------
  # Full lifecycle
  # ---------------------------------------------------------------------------

  describe "full lifecycle" do
    test "movie: detected → search → approved → fetch → fetching_images → download → complete" do
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 550,
               "title" => "Fight Club",
               "release_date" => "1999-10-15"
             })
           ]
         }},
        {"/movie/550", movie_detail()}
      ])

      file = create_watched_file(%{file_path: "/media/pipeline/Fight.Club.1999.BluRay.mkv"})
      assert file.state == :detected

      assert {:ok, result} = process_file(file)
      assert result.state == :complete
      assert result.entity_id != nil

      entity = Ash.get!(Entity, result.entity_id)
      assert entity.type == :movie
      assert entity.name == "Fight Club"
    end

    test "TV episode: detected → search → approved → fetch → download → complete" do
      stub_routes([
        {"/search/tv",
         %{
           "results" => [
             tv_search_result(%{
               "id" => 1396,
               "name" => "Sample Show Eight",
               "first_air_date" => "2008-01-20"
             })
           ]
         }},
        {"/tv/1396", tv_detail()},
        {"/tv/1396/season/1", season_detail()}
      ])

      file =
        create_watched_file(%{
          file_path:
            "/media/pipeline/TV/Sample.Show.Eight/Season.01/Sample.Show.Eight.S01E01.1080p.BluRay.mkv"
        })

      assert {:ok, result} = process_file(file)
      assert result.state == :complete
      assert result.entity_id != nil

      entity = Ash.get!(Entity, result.entity_id, action: :with_associations)
      assert entity.type == :tv_series
      assert entity.name == "Sample Show Eight"
      assert length(entity.seasons) == 1
      assert length(hd(entity.seasons).episodes) == 1
    end

    test "movie in collection: creates series + child movie" do
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 155,
               "title" => "The Shadowy Sentinel",
               "release_date" => "2008-07-18"
             })
           ]
         }},
        {"/movie/155", movie_in_collection_detail()},
        {"/collection/263", collection_detail()}
      ])

      file =
        create_watched_file(%{
          file_path: "/media/pipeline/The.Shadowy.Sentinel.2008.BluRay.mkv"
        })

      assert {:ok, result} = process_file(file)
      assert result.state == :complete

      entity = Ash.get!(Entity, result.entity_id, action: :with_associations)
      assert entity.type == :movie_series
      assert entity.name == "The Shadowy Sentinel Collection"
      assert length(entity.movies) == 1
      assert hd(entity.movies).name == "The Shadowy Sentinel"
    end
  end

  # ---------------------------------------------------------------------------
  # Stops at pending_review
  # ---------------------------------------------------------------------------

  describe "low confidence stops processing" do
    test "low confidence: detected → search → pending_review (stops)" do
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 999,
               "title" => "Completely Different Movie"
             })
           ]
         }},
        {"/search/tv", %{"results" => []}}
      ])

      file = create_watched_file(%{file_path: "/media/pipeline/Fight.Club.1999.BluRay.mkv"})

      assert {:ok, result} = process_file(file)
      assert result.state == :pending_review
      assert result.entity_id == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Error propagation
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "search error: detected → search → error (stops)" do
      stub_tmdb_error("/search/movie", 500)

      file = create_watched_file(%{file_path: "/media/pipeline/Fight.Club.1999.BluRay.mkv"})

      assert {:ok, result} = process_file(file)
      assert result.state == :error
      assert result.error_message != nil
    end

    test "fetch error: approved → fetch_metadata → error (stops)" do
      stub_tmdb_error("/movie/999", 404)

      file =
        create_approved_file(%{
          file_path: "/media/pipeline/fetch_err.mkv",
          tmdb_id: "999",
          parsed_type: :movie
        })

      {:ok, result} =
        file
        |> Ash.Changeset.for_update(:fetch_metadata, %{})
        |> Ash.update()

      assert result.state == :error
      assert result.error_message != nil
    end
  end

  # ---------------------------------------------------------------------------
  # Batch handling
  # ---------------------------------------------------------------------------

  describe "batch entity_id extraction" do
    test "extracts and deduplicates entity_ids from processed files" do
      entity1 = create_entity(%{type: :movie, name: "Movie 1"})
      entity2 = create_entity(%{type: :movie, name: "Movie 2"})

      # Simulate processed files with entity_ids
      files = [
        build_entity_id_data(entity1.id),
        build_entity_id_data(entity1.id),
        build_entity_id_data(entity2.id),
        build_entity_id_data(nil)
      ]

      entity_ids =
        files
        |> Enum.map(& &1.entity_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      assert length(entity_ids) == 2
      assert entity1.id in entity_ids
      assert entity2.id in entity_ids
    end
  end

  defp build_entity_id_data(entity_id) do
    %{entity_id: entity_id}
  end
end
