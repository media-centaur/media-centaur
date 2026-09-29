defmodule MediaCentaur.PipelineTest do
  @moduledoc """
  End-to-end pipeline flow tests. Calls `Discovery.process/1` and
  `Import.process_payload/1` directly (without Broadway) to verify the full
  parse → search → fetch_metadata → publish lifecycle.

  After Import publishes the entity event, the test subscribes and calls
  `Library.Inbound.ingest/1` directly (in the test process) to verify
  entity creation within the sandbox.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Inbound
  alias MediaCentaur.Pipeline.{Discovery, Import}
  alias MediaCentaur.Pipeline.Import.Producer, as: ImportProducer
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Review
  alias MediaCentaur.Review.FileEventHandler

  import MediaCentaur.TmdbStubs

  setup do
    # PubSub listener GenServers don't start in test mode (no sandbox
    # access). This integration test needs Review.Intake to process
    # {:needs_review, ...} and {:review_completed, ...} events, so each test
    # starts its own, stopped with the test.
    start_supervised!(MediaCentaur.Review.Intake)
    # Review closes and reopens its items on the library's link outcomes
    # (`library:file_events`), so the review-resolved tests run its handler.
    start_supervised!(FileEventHandler)
    setup_tmdb_client()

    # Subscribe to receive entity_published events from the Import pipeline
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_publish())

    # Register media_dir_images for paths used in test payloads.
    # Images go to a temp dir that gets cleaned up after each test.
    images_dir = Path.join(System.tmp_dir!(), "pipeline_test_#{Ecto.UUID.generate()}")
    File.mkdir_p!(images_dir)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    updated_config =
      Map.put(config, :media_dir_images, %{
        "/media/pipeline" => images_dir,
        "/media/pipeline/TV" => images_dir
      })

    :persistent_term.put({MediaCentaur.Settings.Config, :config}, updated_config)

    on_exit(fn -> File.rm_rf!(images_dir) end)

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
               "title" => "Sample Movie",
               "release_date" => "1999-10-15"
             })
           ]
         }},
        {"/movie/550", movie_detail()}
      ])

      payload = %Payload{
        file_path: "/media/pipeline/Sample.Movie.1999.BluRay.mkv",
        media_directory: "/media/pipeline"
      }

      assert {:matched, discovered} = Discovery.process(payload)
      assert discovered.tmdb_id == 550
      assert discovered.tmdb_type == :movie

      import_payload =
        ImportProducer.build_payload(%{
          file_path: discovered.file_path,
          media_dir: discovered.media_directory,
          tmdb_id: discovered.tmdb_id,
          tmdb_type: discovered.tmdb_type,
          season: discovered.parsed.season,
          episode: discovered.parsed.episode
        })

      assert {:ok, _result} = Import.process_payload(import_payload)

      # Entity creation is async via PubSub — process in-test for sandbox
      assert_receive {:entity_published, event}
      assert {:ok, entity, :new, _images} = Inbound.ingest(event)

      assert %Library.Movie{} = entity
      assert entity.name == "Sample Movie"

      # WatchedFile created by Inbound.ingest, linked via PlayableItem
      # (Library Schema v2 Phase 2 Task B).
      files = Library.Files.list_all()
      assert length(files) == 1
      file = hd(files)
      assert Library.Files.top_level_entity_id(file) == entity.id
      assert file.file_path == "/media/pipeline/Sample.Movie.1999.BluRay.mkv"
    end

    test "TV episode: discovery matches → import creates series with season and episode" do
      stub_routes([
        {"/search/tv",
         %{
           "results" => [
             tv_search_result(%{
               "id" => 1396,
               "name" => "Sample Show",
               "first_air_date" => "2008-01-20"
             })
           ]
         }},
        {"/tv/1396", tv_detail()},
        {"/tv/1396/season/1", season_detail()}
      ])

      payload = %Payload{
        file_path: "/media/pipeline/TV/Sample.Show/Season.01/Sample.Show.S01E01.1080p.BluRay.mkv",
        media_directory: "/media/pipeline/TV"
      }

      assert {:matched, discovered} = Discovery.process(payload)

      import_payload =
        ImportProducer.build_payload(%{
          file_path: discovered.file_path,
          media_dir: discovered.media_directory,
          tmdb_id: discovered.tmdb_id,
          tmdb_type: discovered.tmdb_type,
          season: discovered.parsed.season,
          episode: discovered.parsed.episode
        })

      assert {:ok, _result} = Import.process_payload(import_payload)

      assert_receive {:entity_published, event}
      assert {:ok, tv_series, :new, _images} = Inbound.ingest(event)

      assert %Library.TVSeries{} = tv_series
      assert tv_series.name == "Sample Show"
      tv_series = MediaCentaur.Repo.preload(tv_series, seasons: :episodes)
      assert length(tv_series.seasons) == 1
      assert length(hd(tv_series.seasons).episodes) == 1
    end

    test "movie in collection: creates series + child movie" do
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 155,
               "title" => "Sample Movie Two",
               "release_date" => "2008-07-18"
             })
           ]
         }},
        {"/movie/155", movie_in_collection_detail()},
        {"/collection/263", collection_detail()}
      ])

      payload = %Payload{
        file_path: "/media/pipeline/Sample.Movie.Two.2008.BluRay.mkv",
        media_directory: "/media/pipeline"
      }

      assert {:matched, discovered} = Discovery.process(payload)

      import_payload =
        ImportProducer.build_payload(%{
          file_path: discovered.file_path,
          media_dir: discovered.media_directory,
          tmdb_id: discovered.tmdb_id,
          tmdb_type: discovered.tmdb_type,
          season: discovered.parsed.season,
          episode: discovered.parsed.episode
        })

      assert {:ok, _result} = Import.process_payload(import_payload)

      assert_receive {:entity_published, event}
      assert {:ok, movie_series, :new, _images} = Inbound.ingest(event)

      assert %Library.MovieSeries{} = movie_series
      assert movie_series.name == "Sample Movie Collection"
      movie_series = MediaCentaur.Repo.preload(movie_series, :movies)
      assert length(movie_series.movies) == 1
      assert hd(movie_series.movies).name == "Sample Movie Two"
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

      # Subscribe to confirm Intake processes the event
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.review_updates())

      payload = %Payload{
        file_path: "/media/pipeline/Sample.Movie.1999.BluRay.mkv",
        media_directory: "/media/pipeline"
      }

      assert {:needs_review, result} = Discovery.process(payload)
      assert result.entity_id == nil

      # Wait for Intake GenServer to process the PubSub event
      assert_receive {:file_added, %MediaCentaur.Review.Events.FileAdded{}}, 1000

      # PendingFile created
      pending_files = Review.list_pending_files_for_review()
      assert length(pending_files) == 1
      pending = hd(pending_files)
      assert pending.file_path == "/media/pipeline/Sample.Movie.1999.BluRay.mkv"
      assert pending.status == :pending

      # No WatchedFile created
      assert Library.Files.list_all() == []
    end
  end

  # ---------------------------------------------------------------------------
  # Error propagation
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "discovery search error: returns error, no WatchedFile, no PendingFile" do
      stub_tmdb_error("/search/movie", 500)

      payload = %Payload{
        file_path: "/media/pipeline/Sample.Movie.1999.BluRay.mkv",
        media_directory: "/media/pipeline"
      }

      assert {:error, _reason} = Discovery.process(payload)

      # No WatchedFile or PendingFile created
      assert Library.Files.list_all() == []
      assert Review.list_pending_files() == []
    end
  end

  # ---------------------------------------------------------------------------
  # Dedup check
  # ---------------------------------------------------------------------------

  describe "dedup" do
    test "discovery skips already-linked file" do
      entity = create_entity(%{type: :movie, name: "Already Ingested"})

      create_linked_file(%{
        file_path: "/media/pipeline/Already.Ingested.mkv",
        media_dir: "/media/pipeline",
        movie_id: entity.id
      })

      payload = %Payload{
        file_path: "/media/pipeline/Already.Ingested.mkv",
        media_directory: "/media/pipeline"
      }

      assert :skipped = Discovery.process(payload)

      # Still only one WatchedFile
      assert length(Library.Files.list_all()) == 1
    end

    test "discovery skips a file dismissed in review, without searching TMDB" do
      # Dismiss is a person deciding the file is not library content —
      # a terminal answer, same as being linked. Re-searching it is
      # work whose result can never be used: `add_pending_file/1` keys
      # on file_path and returns the existing dismissed row, so the
      # match is computed and thrown away on every scan and restart.
      #
      # No TMDB stub is installed on purpose. Under ADR-016 an
      # unstubbed request fails loudly, so `:skipped` is proof the
      # search never ran — not merely that its result was ignored.
      path = "/media/pipeline/Sample.Capture.2025-06-29.mkv"
      pending = create_pending_file(%{file_path: path, media_directory: "/media/pipeline"})
      {:ok, _dismissed} = Review.dismiss(pending)

      payload = %Payload{file_path: path, media_directory: "/media/pipeline"}

      assert :skipped = Discovery.process(payload)
      assert Review.count_pending() == 0
    end

    test "discovery does not skip a file still awaiting review" do
      # The counterpart: a pending row is an open question, not a
      # decision. `rescan_unlinked/0` exists to re-run these once a
      # transient failure (a rejected TMDB key) is resolved, so they
      # have to stay searchable.
      path = "/media/pipeline/Sample.Movie.2010.mkv"
      create_pending_file(%{file_path: path, media_directory: "/media/pipeline"})

      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 4242,
               "title" => "Sample Movie",
               "release_date" => "2010-03-01"
             })
           ]
         }},
        {"/search/tv", %{"results" => []}}
      ])

      payload = %Payload{file_path: path, media_directory: "/media/pipeline"}

      refute Discovery.process(payload) == :skipped
    end

    # 2026-09-29 regression: a file parked in the episode-mapping queue has a
    # known identity and waits for a person to place it. Startup recovery
    # re-sends every unlinked file, and Discovery searched it again; a
    # low-confidence result put it back in Review beside its mapping entry,
    # on every restart. No TMDB stub: `:skipped` proves the search never ran.
    test "discovery skips a file waiting in the episode-mapping queue, without searching TMDB" do
      path = "/media/pipeline/TV/Sample Show/Sample.Show.S03E01.mkv"

      {:ok, _awaiting} =
        MediaCentaur.EpisodeMapping.divert(%{
          file_path: path,
          media_dir: "/media/pipeline/TV",
          tmdb_id: 4242,
          claimed_season: 3,
          claimed_episode: 1
        })

      payload = %Payload{file_path: path, media_directory: "/media/pipeline/TV"}

      assert :skipped = Discovery.process(payload)
      assert Review.count_pending() == 0
    end

    test "discovery skips a file dismissed in the episode-mapping queue" do
      path = "/media/pipeline/TV/Sample Show/Sample.Show.S03E02.mkv"

      {:ok, awaiting} =
        MediaCentaur.EpisodeMapping.divert(%{
          file_path: path,
          media_dir: "/media/pipeline/TV",
          tmdb_id: 4242,
          claimed_season: 3,
          claimed_episode: 2
        })

      {:ok, _dismissed} = MediaCentaur.EpisodeMapping.dismiss_awaiting(awaiting)

      payload = %Payload{file_path: path, media_directory: "/media/pipeline/TV"}

      assert :skipped = Discovery.process(payload)
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
          media_directory: "/media/pipeline",
          parsed_title: "Review Resolved",
          tmdb_id: 550,
          tmdb_type: "movie",
          confidence: 1.0,
          match_title: "Sample Movie"
        })

      import_payload =
        ImportProducer.build_payload(%{
          file_path: "/media/pipeline/Review.Resolved.mkv",
          media_dir: "/media/pipeline",
          tmdb_id: 550,
          tmdb_type: :movie,
          season: nil,
          episode: nil
        })

      assert {:ok, _result} = Import.process_payload(import_payload)

      assert_receive {:entity_published, event}
      assert {:ok, entity, :new, _images} = Inbound.ingest(event)

      assert %Library.Movie{} = entity
      assert entity.name == "Sample Movie"

      # WatchedFile created by Inbound.ingest, linked via PlayableItem.
      files = Library.Files.list_all()
      assert length(files) == 1
      assert Library.Files.top_level_entity_id(hd(files)) == entity.id

      # PendingFile destroyed once the library reports the file linked
      FileEventHandler.__sync_for_test__()
      assert Review.list_pending_files() == []
      refute Repo.get(Review.PendingFile, pending.id)
    end

    # The reported case: a yearly special parses as a movie with no season or
    # episode, its series is the match, and the library has no episode to
    # attach it to. Regression: the review item was deleted as soon as the
    # entity was published, the series stayed hidden for want of a file, and
    # the item came back only after a restart — without the chosen match.
    #
    # Changed 2026-09-29 (campaign `review-coherence`): the file used to
    # return to Review with the reason, where the reviewer chose its
    # episode. A position is now decided in one place, so Import parks the
    # file in the episode-mapping queue with the year its name claims, and
    # the review item closes. The regression — an item gone and a title
    # absent — is still guarded: the file is held by a queue, never dropped.
    test "a series match for a file with no season and episode is parked for episode mapping" do
      stub_routes([
        {"/tv/1396", tv_detail(%{"seasons" => [%{"season_number" => 1}]})}
      ])

      path = "/media/pipeline/TV/Sample Special 2025/Sample.Special.2025.1080p.WEBRip.mp4"

      pending =
        create_pending_file(%{
          file_path: path,
          media_directory: "/media/pipeline/TV",
          parsed_title: "Sample Special",
          parsed_type: "movie",
          tmdb_id: 1396,
          tmdb_type: "tv",
          match_title: "Sample Show"
        })

      import_payload =
        ImportProducer.build_payload(%{
          file_path: path,
          media_dir: "/media/pipeline/TV",
          tmdb_id: 1396,
          tmdb_type: :tv,
          season: nil,
          episode: nil
        })

      assert {:ok, _result} = Import.process_payload(import_payload)

      assert_receive {:entity_published, %{parked: true} = event}
      assert {:ok, _tv_series, :new, _images} = Inbound.ingest(event)

      FileEventHandler.__sync_for_test__()

      refute Library.Files.linked?(path)
      refute Repo.get(Review.PendingFile, pending.id)

      assert [%{file_path: ^path, tmdb_id: 1396, claimed_year: 2025}] =
               MediaCentaur.EpisodeMapping.list_awaiting()
    end

    # The match decides which episode a file is, not the filename: a
    # reviewer's episode choice has to reach the library.
    test "the match's season and episode place the file, whatever its name says" do
      stub_routes([
        {"/tv/1396", tv_detail()},
        {"/tv/1396/season/1", season_detail()}
      ])

      path = "/media/pipeline/TV/Sample Special 2025/Sample.Special.2025.1080p.WEBRip.mp4"

      import_payload =
        ImportProducer.build_payload(%{
          file_path: path,
          media_dir: "/media/pipeline/TV",
          tmdb_id: 1396,
          tmdb_type: :tv,
          season: 1,
          episode: 1
        })

      assert {:ok, _result} = Import.process_payload(import_payload)

      assert_receive {:entity_published, event}
      assert {:ok, tv_series, :new, _images} = Inbound.ingest(event)

      assert Library.Files.linked?(path)
      tv_series = Repo.preload(tv_series, seasons: :episodes)
      assert [%{season_number: 1, episodes: [%{episode_number: 1}]}] = tv_series.seasons
    end

    # An import that fails before the library never produces a link, so it
    # reports the outcome itself. Regression: the review item stayed
    # `:approved` — a status the queue does not list — with nothing retrying.
    test "an import that fails returns its review item with the reason" do
      path = "/media/pipeline/Review.Failed.mkv"

      pending =
        create_pending_file(%{
          file_path: path,
          media_directory: "/media/pipeline",
          tmdb_id: 550,
          tmdb_type: "movie"
        })

      {:ok, _approved} = Review.approve_pending_file(pending)

      import_payload =
        ImportProducer.build_payload(%{
          file_path: path,
          media_dir: "/media/pipeline",
          tmdb_id: 550,
          tmdb_type: :movie,
          season: nil,
          episode: nil
        })

      failed =
        Broadway.Message.failed(
          %Broadway.Message{data: import_payload, acknowledger: Broadway.NoopAcknowledger.init()},
          :insufficient_disk_space
        )

      Import.handle_failed([failed], nil)
      FileEventHandler.__sync_for_test__()

      reopened = Repo.get!(Review.PendingFile, pending.id)
      assert reopened.status == :pending
      assert reopened.error_message =~ "disk space"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch handling
  # ---------------------------------------------------------------------------

  describe "discovery batch broadcast" do
    # A needs_review payload with a candidate still carries `tmdb_id` and
    # `confidence` (the review UI needs them for its preselected match), so
    # the batcher must discriminate on the discovery outcome — not on field
    # presence. Regression: a below-threshold match was both queued for
    # review AND broadcast for import, importing the file behind the
    # reviewer's back and stranding the PendingFile.
    test "does not broadcast a needs_review payload as file_matched" do
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

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())

      payload = %Payload{
        file_path: "/media/pipeline/Sample.Movie.1999.BluRay.mkv",
        media_directory: "/media/pipeline"
      }

      assert {:needs_review, result} = Discovery.process(payload)
      assert result.tmdb_id == 999
      assert result.confidence != nil

      Discovery.handle_batch(:default, [batch_message(result)], batch_info(), nil)

      refute_receive {:file_matched, _}, 200
    end

    test "broadcasts a matched payload as file_matched" do
      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 550,
               "title" => "Sample Movie",
               "release_date" => "1999-10-15"
             })
           ]
         }}
      ])

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())

      payload = %Payload{
        file_path: "/media/pipeline/Sample.Movie.1999.BluRay.mkv",
        media_directory: "/media/pipeline"
      }

      assert {:matched, result} = Discovery.process(payload)

      Discovery.handle_batch(:default, [batch_message(result)], batch_info(), nil)

      assert_receive {:file_matched, matched}
      assert matched.tmdb_id == 550
      assert matched.file_path == "/media/pipeline/Sample.Movie.1999.BluRay.mkv"
    end

    # A file awaiting review is re-run by `rescan_unlinked/0`. When the new
    # run matches with confidence and the file is linked, its open review is
    # answered. Regression: the file imported and its row stayed in the
    # review queue forever.
    test "a queued file that a re-run matches and links leaves the review queue" do
      path = "/media/pipeline/Sample.Movie.1999.BluRay.mkv"
      pending = create_pending_file(%{file_path: path, media_directory: "/media/pipeline"})

      stub_routes([
        {"/search/movie",
         %{
           "results" => [
             movie_search_result(%{
               "id" => 550,
               "title" => "Sample Movie",
               "release_date" => "1999-10-15"
             })
           ]
         }}
      ])

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_matched())

      payload = %Payload{file_path: path, media_directory: "/media/pipeline"}

      assert {:matched, result} = Discovery.process(payload)

      Discovery.handle_batch(:default, [batch_message(result)], batch_info(), nil)

      assert_receive {:file_matched, matched}
      stub_routes([{"/movie/550", movie_detail()}])
      assert {:ok, _result} = Import.process_payload(ImportProducer.build_payload(matched))

      assert_receive {:entity_published, event}
      assert {:ok, _movie, :new, _images} = Inbound.ingest(event)

      FileEventHandler.__sync_for_test__()
      refute Repo.get(Review.PendingFile, pending.id)
    end
  end

  defp batch_message(payload) do
    %Broadway.Message{data: payload, acknowledger: Broadway.NoopAcknowledger.init()}
  end

  defp batch_info do
    %Broadway.BatchInfo{batcher: :default, size: 1}
  end

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
