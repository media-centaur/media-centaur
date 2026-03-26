defmodule MediaCentaur.PipelineTest do
  @moduledoc """
  End-to-end pipeline flow tests. Calls `Discovery.process/1` and
  `Import.process/1` directly (without Broadway) to verify the full
  parse → search → fetch_metadata → ingest lifecycle.
  """
  use MediaCentaur.DataCase

  alias MediaCentaur.Library
  alias MediaCentaur.Pipeline.{Discovery, Import}
  alias MediaCentaur.Pipeline.Import.Producer, as: ImportProducer
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Review

  import MediaCentaur.TmdbStubs

  setup do
    setup_tmdb_client()

    # Register watch_dir_images for paths used in test payloads.
    # Images go to a temp dir that gets cleaned up after each test.
    images_dir = Path.join(System.tmp_dir!(), "pipeline_test_#{Ecto.UUID.generate()}")
    File.mkdir_p!(images_dir)

    config = :persistent_term.get({MediaCentaur.Config, :config})

    updated_config =
      Map.put(config, :watch_dir_images, %{
        "/media/pipeline" => images_dir,
        "/media/pipeline/TV" => images_dir
      })

    :persistent_term.put({MediaCentaur.Config, :config}, updated_config)

    on_exit(fn ->
      File.rm_rf!(images_dir)
      :persistent_term.put({MediaCentaur.Config, :config}, config)
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Discovery → Import full lifecycle
  # ---------------------------------------------------------------------------

  describe "full lifecycle" do
    test "movie: discovery matches → import fetches metadata and creates entity" do
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

      payload = %Payload{
        file_path: "/media/pipeline/Fight.Club.1999.BluRay.mkv",
        watch_directory: "/media/pipeline"
      }

      assert {:matched, discovered} = Discovery.process(payload)
      assert discovered.tmdb_id == 550
      assert discovered.tmdb_type == :movie

      import_payload =
        ImportProducer.build_payload(%{
          file_path: discovered.file_path,
          watch_dir: discovered.watch_directory,
          tmdb_id: discovered.tmdb_id,
          tmdb_type: discovered.tmdb_type,
          pending_file_id: nil
        })

      assert {:ok, result} = Import.process(import_payload)
      assert result.entity_id != nil

      entity = Library.get_entity!(result.entity_id)
      assert entity.type == :movie
      assert entity.name == "Fight Club"

      # WatchedFile created via :link_file
      files = Library.list_watched_files!()
      assert length(files) == 1
      file = hd(files)
      assert file.entity_id == result.entity_id
      assert file.file_path == "/media/pipeline/Fight.Club.1999.BluRay.mkv"
    end

    test "TV episode: discovery matches → import creates series with season and episode" do
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

      payload = %Payload{
        file_path:
          "/media/pipeline/TV/Sample.Show.Eight/Season.01/Sample.Show.Eight.S01E01.1080p.BluRay.mkv",
        watch_directory: "/media/pipeline/TV"
      }

      assert {:matched, discovered} = Discovery.process(payload)

      import_payload =
        ImportProducer.build_payload(%{
          file_path: discovered.file_path,
          watch_dir: discovered.watch_directory,
          tmdb_id: discovered.tmdb_id,
          tmdb_type: discovered.tmdb_type,
          pending_file_id: nil
        })

      assert {:ok, result} = Import.process(import_payload)
      assert result.entity_id != nil

      entity = Library.get_entity_with_associations!(result.entity_id)
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

      payload = %Payload{
        file_path: "/media/pipeline/The.Shadowy.Sentinel.2008.BluRay.mkv",
        watch_directory: "/media/pipeline"
      }

      assert {:matched, discovered} = Discovery.process(payload)

      import_payload =
        ImportProducer.build_payload(%{
          file_path: discovered.file_path,
          watch_dir: discovered.watch_directory,
          tmdb_id: discovered.tmdb_id,
          tmdb_type: discovered.tmdb_type,
          pending_file_id: nil
        })

      assert {:ok, result} = Import.process(import_payload)

      entity = Library.get_entity_with_associations!(result.entity_id)
      assert entity.type == :movie_series
      assert entity.name == "The Shadowy Sentinel Collection"
      assert length(entity.movies) == 1
      assert hd(entity.movies).name == "The Shadowy Sentinel"
    end
  end

  # ---------------------------------------------------------------------------
  # Discovery stops at pending_review
  # ---------------------------------------------------------------------------

  describe "low confidence stops at discovery" do
    test "low confidence: search → needs_review + PendingFile created, no WatchedFile" do
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

      payload = %Payload{
        file_path: "/media/pipeline/Fight.Club.1999.BluRay.mkv",
        watch_directory: "/media/pipeline"
      }

      assert {:needs_review, result} = Discovery.process(payload)
      assert result.entity_id == nil

      # PendingFile created
      pending_files = Review.list_pending_files_for_review!()
      assert length(pending_files) == 1
      pending = hd(pending_files)
      assert pending.file_path == "/media/pipeline/Fight.Club.1999.BluRay.mkv"
      assert pending.status == :pending

      # No WatchedFile created
      assert Library.list_watched_files!() == []
    end
  end

  # ---------------------------------------------------------------------------
  # Error propagation
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "discovery search error: returns error, no WatchedFile, no PendingFile" do
      stub_tmdb_error("/search/movie", 500)

      payload = %Payload{
        file_path: "/media/pipeline/Fight.Club.1999.BluRay.mkv",
        watch_directory: "/media/pipeline"
      }

      assert {:error, _reason} = Discovery.process(payload)

      # No WatchedFile or PendingFile created
      assert Library.list_watched_files!() == []
      assert Review.list_pending_files!() == []
    end
  end

  # ---------------------------------------------------------------------------
  # Dedup check
  # ---------------------------------------------------------------------------

  describe "dedup" do
    test "discovery skips already-linked file" do
      entity = create_entity(%{type: :movie, name: "Already Ingested"})

      Library.link_file!(%{
        file_path: "/media/pipeline/Already.Ingested.mkv",
        watch_dir: "/media/pipeline",
        entity_id: entity.id
      })

      payload = %Payload{
        file_path: "/media/pipeline/Already.Ingested.mkv",
        watch_directory: "/media/pipeline"
      }

      assert :skipped = Discovery.process(payload)

      # Still only one WatchedFile
      assert length(Library.list_watched_files!()) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Review resolved (Import pipeline directly)
  # ---------------------------------------------------------------------------

  describe "review resolved" do
    test "import processes with tmdb_id, creates entity, destroys PendingFile" do
      stub_routes([
        {"/movie/550", movie_detail()}
      ])

      # Create PendingFile first
      {:ok, pending} =
        Review.create_pending_file(%{
          file_path: "/media/pipeline/Review.Resolved.mkv",
          watch_directory: "/media/pipeline",
          parsed_title: "Review Resolved",
          tmdb_id: 550,
          tmdb_type: "movie",
          confidence: 1.0,
          match_title: "Fight Club"
        })

      import_payload =
        ImportProducer.build_payload(%{
          file_path: "/media/pipeline/Review.Resolved.mkv",
          watch_dir: "/media/pipeline",
          tmdb_id: 550,
          tmdb_type: :movie,
          pending_file_id: pending.id
        })

      assert {:ok, result} = Import.process(import_payload)
      assert result.entity_id != nil

      entity = Library.get_entity!(result.entity_id)
      assert entity.type == :movie
      assert entity.name == "Fight Club"

      # WatchedFile created
      files = Library.list_watched_files!()
      assert length(files) == 1
      assert hd(files).entity_id == result.entity_id

      # PendingFile destroyed
      assert Review.list_pending_files!() == []
    end
  end

  # ---------------------------------------------------------------------------
  # Batch handling
  # ---------------------------------------------------------------------------

  describe "batch entity_id extraction" do
    test "extracts and deduplicates entity_ids from payloads" do
      entity1 = create_entity(%{type: :movie, name: "Movie 1"})
      entity2 = create_entity(%{type: :movie, name: "Movie 2"})

      payloads = [
        %Payload{entity_id: entity1.id},
        %Payload{entity_id: entity1.id},
        %Payload{entity_id: entity2.id},
        %Payload{entity_id: nil}
      ]

      entity_ids =
        payloads
        |> Enum.map(& &1.entity_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      assert length(entity_ids) == 2
      assert entity1.id in entity_ids
      assert entity2.id in entity_ids
    end
  end
end
