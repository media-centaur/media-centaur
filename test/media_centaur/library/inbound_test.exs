defmodule MediaCentaur.Library.InboundTest do
  @moduledoc """
  Tests for Library.Inbound — the library's inbound API for the pipeline.

  No TMDB stubs needed: Inbound consumes pre-built metadata maps, not
  TMDB data. Tests construct event maps directly and call `ingest/1`.

  Inbound also creates WatchedFile records, queues images for download,
  and broadcasts entity changes — but those are integration concerns
  tested via the pipeline end-to-end, not here.
  """
  use MediaCentaur.DataCase

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Inbound

  # ---------------------------------------------------------------------------
  # Event builders
  # ---------------------------------------------------------------------------

  defp movie_event(overrides \\ %{}) do
    defaults = %{
      entity_type: :movie,
      entity_attrs: %{
        type: :movie,
        name: "Fight Club",
        description: "An insomniac office worker...",
        date_published: "1999-10-15",
        content_url: "/media/Fight.Club.1999.mkv",
        url: "https://www.themoviedb.org/movie/550"
      },
      images: [
        %{role: "poster", url: "https://image.tmdb.org/poster.jpg"},
        %{role: "backdrop", url: "https://image.tmdb.org/backdrop.jpg"}
      ],
      identifier: %{property_id: "tmdb", value: "550"},
      child_movie: nil,
      season: nil,
      extra: nil,
      file_path: "/media/Fight.Club.1999.mkv",
      watch_dir: "/media"
    }

    Map.merge(defaults, Enum.into(overrides, %{}))
  end

  defp collection_event(overrides \\ %{}) do
    defaults = %{
      entity_type: :movie_series,
      entity_attrs: %{
        type: :movie_series,
        name: "The Shadowy Sentinel Collection"
      },
      images: [
        %{role: "poster", url: "https://image.tmdb.org/coll_poster.jpg"}
      ],
      identifier: %{property_id: "tmdb_collection", value: "263"},
      child_movie: %{
        attrs: %{
          tmdb_id: "155",
          name: "The Shadowy Sentinel",
          description: "Batman raises the stakes...",
          date_published: "2008-07-18",
          content_url: "/media/The.Shadowy.Sentinel.2008.mkv",
          url: "https://www.themoviedb.org/movie/155",
          position: 1
        },
        images: [
          %{role: "poster", url: "https://image.tmdb.org/dk_poster.jpg"}
        ],
        identifier: %{property_id: "tmdb", value: "155"}
      },
      season: nil,
      extra: nil,
      file_path: "/media/The.Shadowy.Sentinel.2008.mkv",
      watch_dir: "/media"
    }

    Map.merge(defaults, Enum.into(overrides, %{}))
  end

  defp tv_event(overrides \\ %{}) do
    defaults = %{
      entity_type: :tv_series,
      entity_attrs: %{
        type: :tv_series,
        name: "Sample Show Eight",
        description: "A high school chemistry teacher...",
        number_of_seasons: 5,
        url: "https://www.themoviedb.org/tv/1396"
      },
      images: [
        %{role: "poster", url: "https://image.tmdb.org/bb_poster.jpg"}
      ],
      identifier: %{property_id: "tmdb", value: "1396"},
      child_movie: nil,
      season: %{
        season_number: 1,
        name: "Season 1",
        number_of_episodes: 7,
        episode: %{
          attrs: %{
            episode_number: 1,
            name: "Pilot",
            description: "Walter White begins cooking meth.",
            duration: "PT58M",
            content_url: "/media/TV/Sample.Show.Eight.S01E01.mkv"
          },
          images: [
            %{role: "thumb", url: "https://image.tmdb.org/ep_thumb.jpg"}
          ]
        }
      },
      extra: nil,
      file_path: "/media/TV/Sample.Show.Eight.S01E01.mkv",
      watch_dir: "/media/TV"
    }

    Map.merge(defaults, Enum.into(overrides, %{}))
  end

  # ---------------------------------------------------------------------------
  # Standalone movie
  # ---------------------------------------------------------------------------

  describe "standalone movie" do
    test "creates entity and identifier, returns pending images" do
      assert {:ok, entity, :new, pending_images} = Inbound.ingest(movie_event())

      assert entity.type == :movie
      assert entity.name == "Fight Club"
      assert entity.content_url == "/media/Fight.Club.1999.mkv"

      # Identifier created
      assert {:ok, identifier} = find_identifier("tmdb", "550")
      assert identifier.entity_id == entity.id

      # Images collected for queue (not created in DB)
      assert length(pending_images) == 2
      roles = Enum.map(pending_images, & &1.role) |> Enum.sort()
      assert roles == ["backdrop", "poster"]

      assert Enum.all?(pending_images, fn img ->
               img.owner_id == entity.id and img.owner_type == "entity"
             end)
    end

    test "pending images carry source_url from event" do
      event =
        movie_event(
          images: [
            %{role: "poster", url: "https://image.tmdb.org/poster.jpg"}
          ]
        )

      assert {:ok, entity, :new, pending_images} = Inbound.ingest(event)

      assert [image] = pending_images
      assert image.source_url == "https://image.tmdb.org/poster.jpg"
      assert image.owner_id == entity.id
      assert image.owner_type == "entity"
      assert image.role == "poster"
      assert image.extension == "jpg"
    end
  end

  # ---------------------------------------------------------------------------
  # Movie in collection
  # ---------------------------------------------------------------------------

  describe "movie in collection" do
    test "creates movie_series + child movie + identifiers, returns pending images" do
      assert {:ok, entity, :new, pending_images} = Inbound.ingest(collection_event())

      assert entity.type == :movie_series
      assert entity.name == "The Shadowy Sentinel Collection"

      # Collection identifier
      assert {:ok, collection_id} = find_identifier("tmdb_collection", "263")
      assert collection_id.entity_id == entity.id

      # Movie-level TMDB identifier
      assert {:ok, movie_id} = find_identifier("tmdb", "155")
      assert movie_id.entity_id == entity.id

      # Child movie
      entity = MediaCentaur.Repo.preload(entity, [:movies])
      assert length(entity.movies) == 1
      movie = hd(entity.movies)
      assert movie.name == "The Shadowy Sentinel"
      assert movie.content_url == "/media/The.Shadowy.Sentinel.2008.mkv"
      assert movie.position == 1

      # Pending images include entity + child movie images
      assert length(pending_images) == 2
      entity_image = Enum.find(pending_images, &(&1.owner_type == "entity"))
      movie_image = Enum.find(pending_images, &(&1.owner_type == "movie"))
      assert entity_image.role == "poster"
      assert movie_image.role == "poster"
      assert movie_image.owner_id == movie.id
    end

    test "existing movie series — adds new child movie" do
      # Pre-create the series entity and collection identifier
      series = create_entity(%{type: :movie_series, name: "The Shadowy Sentinel Collection"})
      create_identifier(%{entity_id: series.id, property_id: "tmdb_collection", value: "263"})

      event =
        collection_event(
          child_movie: %{
            attrs: %{
              tmdb_id: "49026",
              name: "The Shadowy Sentinel Rises",
              description: "Eight years after the Joker...",
              date_published: "2012-07-20",
              content_url: "/media/The.Shadowy.Sentinel.Rises.2012.mkv",
              position: 2
            },
            images: [],
            identifier: %{property_id: "tmdb", value: "49026"}
          }
        )

      assert {:ok, entity, :new_child, _pending_images} = Inbound.ingest(event)
      assert entity.id == series.id

      entity = MediaCentaur.Repo.preload(entity, [:movies])
      assert length(entity.movies) == 1
      movie = hd(entity.movies)
      assert movie.name == "The Shadowy Sentinel Rises"
      assert movie.position == 2
    end
  end

  # ---------------------------------------------------------------------------
  # TV series
  # ---------------------------------------------------------------------------

  describe "TV series" do
    test "creates entity, season, episode, returns pending images" do
      assert {:ok, entity, :new, pending_images} = Inbound.ingest(tv_event())

      assert entity.type == :tv_series
      assert entity.name == "Sample Show Eight"

      # Identifier
      assert {:ok, identifier} = find_identifier("tmdb", "1396")
      assert identifier.entity_id == entity.id

      # Season + Episode
      entity = Library.get_entity_with_associations!(entity.id)
      assert length(entity.seasons) == 1
      season = hd(entity.seasons)
      assert season.season_number == 1
      assert length(season.episodes) == 1
      episode = hd(season.episodes)
      assert episode.episode_number == 1
      assert episode.name == "Pilot"
      assert episode.content_url == "/media/TV/Sample.Show.Eight.S01E01.mkv"

      # Pending images: entity poster + episode thumb
      assert length(pending_images) == 2
      entity_image = Enum.find(pending_images, &(&1.owner_type == "entity"))
      episode_image = Enum.find(pending_images, &(&1.owner_type == "episode"))
      assert entity_image.role == "poster"
      assert episode_image.role == "thumb"
      assert episode_image.owner_id == episode.id
    end

    test "existing TV series — adds new episode to existing season" do
      existing = create_entity(%{type: :tv_series, name: "Sample Show Eight"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "1396"})

      event =
        tv_event(
          season: %{
            season_number: 1,
            name: "Season 1",
            number_of_episodes: 7,
            episode: %{
              attrs: %{
                episode_number: 2,
                name: "Cat's in the Bag...",
                description: "Walt and Jesse attempt to dispose of the bodies.",
                duration: "PT48M",
                content_url: "/media/TV/Sample.Show.Eight.S01E02.mkv"
              },
              images: []
            }
          }
        )

      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(event)
      assert entity.id == existing.id

      entity = Library.get_entity_with_associations!(entity.id)
      assert length(entity.seasons) == 1
      episode = hd(hd(entity.seasons).episodes)
      assert episode.episode_number == 2
      assert episode.content_url == "/media/TV/Sample.Show.Eight.S01E02.mkv"
    end

    test "TV without season/episode — no-op" do
      event = tv_event(season: nil)

      assert {:ok, entity, :new, _pending_images} = Inbound.ingest(event)
      assert entity.type == :tv_series

      entity = Library.get_entity_with_associations!(entity.id)
      assert entity.seasons == []
    end
  end

  # ---------------------------------------------------------------------------
  # Existing entity reuse
  # ---------------------------------------------------------------------------

  describe "existing entity reuse" do
    test "existing movie sets content_url if nil" do
      existing = create_entity(%{type: :movie, name: "Fight Club"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "550"})

      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(movie_event())
      assert entity.id == existing.id

      reloaded = Library.get_entity!(entity.id)
      assert reloaded.content_url == "/media/Fight.Club.1999.mkv"
    end

    test "existing movie with content_url is returned unchanged" do
      existing =
        create_entity(%{type: :movie, name: "Fight Club", content_url: "/media/original.mkv"})

      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "550"})

      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(movie_event())
      assert entity.id == existing.id

      reloaded = Library.get_entity!(entity.id)
      assert reloaded.content_url == "/media/original.mkv"
    end
  end

  # ---------------------------------------------------------------------------
  # Extras
  # ---------------------------------------------------------------------------

  describe "extras" do
    test "extra without season — creates movie entity + extra" do
      event =
        movie_event(
          extra: %{
            name: "Behind the Scenes",
            content_url: "/media/extras/bts.mkv",
            season_number: nil
          }
        )

      assert {:ok, entity, :new, _pending_images} = Inbound.ingest(event)
      assert entity.type == :movie

      # Entity should NOT get the extra's file path as content_url
      assert is_nil(entity.content_url)

      entity = Library.get_entity_with_associations!(entity.id)
      assert length(entity.extras) == 1
      extra = hd(entity.extras)
      assert extra.name == "Behind the Scenes"
      assert extra.content_url == "/media/extras/bts.mkv"
    end

    test "extra with season — creates TV entity + season + extra" do
      event =
        tv_event(
          season: %{
            season_number: 1,
            name: "Season 1",
            number_of_episodes: 7,
            episode: nil
          },
          extra: %{
            name: "Making Of",
            content_url: "/media/extras/making_of.mkv",
            season_number: 1
          }
        )

      assert {:ok, entity, :new, _pending_images} = Inbound.ingest(event)
      assert entity.type == :tv_series

      entity = Library.get_entity_with_associations!(entity.id)
      assert length(entity.seasons) == 1
      season = hd(entity.seasons)
      assert length(season.extras) == 1
      extra = hd(season.extras)
      assert extra.name == "Making Of"
      assert extra.content_url == "/media/extras/making_of.mkv"
    end

    test "extra on existing entity — reuses parent, creates extra only" do
      existing = create_entity(%{type: :movie, name: "Fight Club"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "550"})

      event =
        movie_event(
          extra: %{
            name: "Deleted Scenes",
            content_url: "/media/extras/deleted.mkv",
            season_number: nil
          }
        )

      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(event)
      assert entity.id == existing.id

      entity = Library.get_entity_with_associations!(entity.id)
      assert length(entity.extras) == 1
      assert hd(entity.extras).name == "Deleted Scenes"
    end
  end

  # ---------------------------------------------------------------------------
  # Race-loss recovery
  # ---------------------------------------------------------------------------

  describe "race-loss recovery" do
    test "detects race loss, destroys duplicate, returns winner" do
      # Pre-create a "winner" entity with the same TMDB identifier
      winner = create_entity(%{type: :movie, name: "Fight Club (Winner)"})
      create_identifier(%{entity_id: winner.id, property_id: "tmdb", value: "550"})

      # Inbound will create a new entity, then when creating the identifier
      # it'll find the existing one belongs to winner. It destroys the duplicate
      # and returns the winner via link_to_existing.
      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(movie_event())
      assert entity.id == winner.id

      # The duplicate entity was destroyed — only the winner remains
      {:ok, entities} = Library.list_entities()
      assert length(entities) == 1
      assert hd(entities).id == winner.id
    end
  end

  # ---------------------------------------------------------------------------
  # Post-ingest side effects
  # ---------------------------------------------------------------------------

  describe "post-ingest side effects" do
    test "creates WatchedFile linking file to entity" do
      assert {:ok, entity, :new, _images} = Inbound.ingest(movie_event())

      files = Library.list_watched_files_for_entity!(entity.id)
      assert [file] = files
      assert file.file_path == "/media/Fight.Club.1999.mkv"
      assert file.watch_dir == "/media"
      assert file.entity_id == entity.id
    end

    test "creates ImageQueue entries for pending images" do
      assert {:ok, entity, :new, pending_images} = Inbound.ingest(movie_event())
      assert length(pending_images) == 2

      queue_entries = MediaCentaur.Pipeline.ImageQueue.list_pending(entity.id)
      assert length(queue_entries) == 2

      roles = Enum.map(queue_entries, & &1.role) |> Enum.sort()
      assert roles == ["backdrop", "poster"]

      assert Enum.all?(queue_entries, &(&1.entity_id == entity.id))
      assert Enum.all?(queue_entries, &(&1.status == "pending"))
    end

    test "broadcasts entities_changed to library:updates" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())

      assert {:ok, entity, :new, _images} = Inbound.ingest(movie_event())

      assert_receive {:entities_changed, entity_ids}
      assert entity.id in entity_ids
    end

    test "broadcasts images_pending to pipeline:images" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_images())

      assert {:ok, entity, :new, _images} = Inbound.ingest(movie_event())

      assert_receive {:images_pending, %{entity_id: entity_id, watch_dir: watch_dir}}
      assert entity_id == entity.id
      assert watch_dir == "/media"
    end

    test "skips image queue and broadcast when no images" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_images())

      event = movie_event(images: [])
      assert {:ok, _entity, :new, []} = Inbound.ingest(event)

      refute_receive {:images_pending, _}
    end
  end

  # ---------------------------------------------------------------------------
  # Image ready (from image pipeline)
  # ---------------------------------------------------------------------------

  describe "image_ready" do
    test "creates image record for entity owner" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})

      send_image_ready(%{
        owner_id: entity.id,
        owner_type: "entity",
        role: "poster",
        content_url: "images/#{entity.id}/poster.jpg",
        extension: "jpg",
        entity_id: entity.id
      })

      {:ok, images} = Library.list_images_for_entity(entity.id)
      assert [image] = images
      assert image.role == "poster"
      assert image.content_url == "images/#{entity.id}/poster.jpg"
      assert image.entity_id == entity.id
    end

    test "creates image record for movie owner" do
      entity = create_entity(%{type: :movie_series, name: "Collection"})

      {:ok, movie} =
        Library.find_or_create_movie(%{
          entity_id: entity.id,
          tmdb_id: "155",
          name: "Movie",
          position: 1
        })

      send_image_ready(%{
        owner_id: movie.id,
        owner_type: "movie",
        role: "poster",
        content_url: "images/#{entity.id}/movie_poster.jpg",
        extension: "jpg",
        entity_id: entity.id
      })

      movie = MediaCentaur.Repo.preload(movie, :images)
      assert [image] = movie.images
      assert image.role == "poster"
      assert image.movie_id == movie.id
    end

    test "broadcasts entities_changed after image creation" do
      entity = create_entity(%{type: :movie, name: "Test Movie"})
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())

      send_image_ready(%{
        owner_id: entity.id,
        owner_type: "entity",
        role: "backdrop",
        content_url: "images/#{entity.id}/backdrop.jpg",
        extension: "jpg",
        entity_id: entity.id
      })

      assert_receive {:entities_changed, entity_ids}
      assert entity.id in entity_ids
    end
  end

  # ---------------------------------------------------------------------------
  # Rematch
  # ---------------------------------------------------------------------------

  describe "handle_rematch/1" do
    test "destroys entity and watched files, sends file list to review:intake" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_updates())
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.review_intake())

      entity =
        create_entity(%{
          type: :movie,
          name: "Wrong Movie",
          content_url: "/media/movies/Sample Movie (2017).mkv"
        })

      create_linked_file(%{
        entity: entity,
        file_path: "/media/movies/Sample Movie (2017).mkv",
        watch_dir: "/media/movies"
      })

      assert :ok = Inbound.handle_rematch(entity.id)

      # Entity destroyed
      assert {:error, _} = Library.get_entity(entity.id)

      # WatchedFiles destroyed
      assert Library.list_watched_files_for_entity!(entity.id) == []

      # Broadcasts entities_changed
      assert_received {:entities_changed, [_entity_id]}

      # Sends file list to review:intake
      assert_received {:files_for_review,
                       [
                         %{
                           file_path: "/media/movies/Sample Movie (2017).mkv",
                           watch_dir: "/media/movies"
                         }
                       ]}
    end

    test "sends multiple files for TV series with multiple watched files" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.review_intake())

      entity = create_entity(%{type: :tv_series, name: "Wrong Show"})
      season = create_season(%{entity_id: entity.id, season_number: 1, number_of_episodes: 2})

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E01.mkv"
      })

      create_episode(%{
        season_id: season.id,
        episode_number: 2,
        name: "Second",
        content_url: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E02.mkv"
      })

      create_identifier(%{entity_id: entity.id, property_id: "tmdb", value: "wrong"})

      create_linked_file(%{
        entity: entity,
        file_path: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E01.mkv",
        watch_dir: "/media/tv"
      })

      create_linked_file(%{
        entity: entity,
        file_path: "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E02.mkv",
        watch_dir: "/media/tv"
      })

      assert :ok = Inbound.handle_rematch(entity.id)

      # Entity fully destroyed
      assert {:error, _} = Library.get_entity(entity.id)

      # Both files sent to review
      assert_received {:files_for_review, files}
      assert length(files) == 2
      paths = Enum.map(files, & &1.file_path) |> Enum.sort()

      assert paths == [
               "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E01.mkv",
               "/media/tv/Sample Show One (2001)/Season 1/Sample Show One S01E02.mkv"
             ]
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "nil event raises" do
      assert_raise BadMapError, fn ->
        Inbound.ingest(nil)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp find_identifier(property_id, value) do
    case property_id do
      "tmdb_collection" -> Library.find_by_tmdb_collection(value)
      _ -> Library.find_by_tmdb_id(value)
    end
  end

  defp send_image_ready(attrs) do
    Inbound.process_image_ready(attrs)
  end
end
