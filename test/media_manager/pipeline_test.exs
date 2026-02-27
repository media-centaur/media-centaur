defmodule MediaManager.PipelineTest do
  @moduledoc """
  End-to-end pipeline flow tests. Replicates `Pipeline.process_file/1` logic
  directly (without Broadway) to verify the full parse → search →
  fetch_metadata → download_images → ingest lifecycle using Payload-based
  stage functions.
  """
  use MediaManager.DataCase

  alias MediaManager.Library.Entity
  alias MediaManager.Pipeline.Payload

  alias MediaManager.Pipeline.Stages.{
    Parse,
    Search,
    FetchMetadata,
    DownloadImages,
    Ingest
  }

  alias MediaManager.Review.{Intake, PendingFile}

  import MediaManager.TmdbStubs

  setup do
    setup_tmdb_client()
    :ok
  end

  # Replicates Pipeline.process_file/1 logic for testing
  defp process_file(file) do
    payload = %Payload{
      file_path: file.file_path,
      watch_directory: file.watch_dir,
      entry_point: :file_detected
    }

    case run_pipeline(payload) do
      {:ok, payload} ->
        Ash.update(file, %{state: :complete, entity_id: payload.entity_id}, action: :update_state)

      {:needs_review, payload} ->
        Intake.create_from_payload(payload)

        Ash.update(file, %{state: :pending_review}, action: :update_state)

      {:error, reason} ->
        Ash.update(file, %{state: :error, error_message: inspect(reason)}, action: :update_state)
    end
  end

  defp run_pipeline(payload) do
    with {:ok, payload} <- Parse.run(payload),
         result <- Search.run(payload) do
      case result do
        {:ok, payload} -> run_post_search(payload)
        {:needs_review, _} = needs_review -> needs_review
        {:error, _} = error -> error
      end
    end
  end

  defp run_post_search(payload) do
    with {:ok, payload} <- FetchMetadata.run(payload),
         {:ok, payload} <- DownloadImages.run(payload),
         {:ok, payload} <- Ingest.run(payload) do
      {:ok, payload}
    end
  end

  # ---------------------------------------------------------------------------
  # Full lifecycle
  # ---------------------------------------------------------------------------

  describe "full lifecycle" do
    test "movie: detected → search → fetch → download → ingest → complete" do
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

    test "TV episode: detected → search → fetch → download → ingest → complete" do
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
    test "low confidence: detected → search → pending_review + PendingFile created" do
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

      # Verify PendingFile was created
      pending_files = Ash.read!(PendingFile, action: :pending)
      assert length(pending_files) == 1
      pending = hd(pending_files)
      assert pending.file_path == "/media/pipeline/Fight.Club.1999.BluRay.mkv"
      assert pending.status == :pending
    end
  end

  # ---------------------------------------------------------------------------
  # Error propagation
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "search error: detected → error with error_message" do
      stub_tmdb_error("/search/movie", 500)

      file = create_watched_file(%{file_path: "/media/pipeline/Fight.Club.1999.BluRay.mkv"})

      assert {:ok, result} = process_file(file)
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
