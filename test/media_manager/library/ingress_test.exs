defmodule MediaManager.Library.IngressTest do
  @moduledoc """
  Tests for Library.Ingress — the pipeline's persistence layer.

  No TMDB stubs needed: Ingress doesn't call TMDB. Tests construct
  metadata maps and staged image files directly.
  """
  use MediaManager.DataCase

  alias MediaManager.Library.{Entity, Identifier, Ingress}
  alias MediaManager.Pipeline.Payload

  setup do
    # Set up a temporary images directory for each test.
    # Config.get reads from :persistent_term, so we override it directly.
    images_dir = Path.join(System.tmp_dir!(), "ingress_test_#{Ash.UUID.generate()}")
    File.mkdir_p!(images_dir)

    config = :persistent_term.get({MediaManager.Config, :config})
    updated_config = Map.put(config, :media_images_dir, images_dir)
    :persistent_term.put({MediaManager.Config, :config}, updated_config)

    on_exit(fn ->
      File.rm_rf!(images_dir)
      :persistent_term.put({MediaManager.Config, :config}, config)
    end)

    %{images_dir: images_dir}
  end

  # ---------------------------------------------------------------------------
  # Metadata builders
  # ---------------------------------------------------------------------------

  defp movie_metadata(overrides \\ %{}) do
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
        %{role: "poster", url: "https://image.tmdb.org/poster.jpg", extension: "jpg"},
        %{role: "backdrop", url: "https://image.tmdb.org/backdrop.jpg", extension: "jpg"}
      ],
      identifier: %{property_id: "tmdb", value: "550"},
      child_movie: nil,
      season: nil,
      extra: nil
    }

    Map.merge(defaults, Enum.into(overrides, %{}))
  end

  defp collection_metadata(overrides \\ %{}) do
    defaults = %{
      entity_type: :movie_series,
      entity_attrs: %{
        type: :movie_series,
        name: "The Shadowy Sentinel Collection"
      },
      images: [
        %{role: "poster", url: "https://image.tmdb.org/coll_poster.jpg", extension: "jpg"}
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
          %{role: "poster", url: "https://image.tmdb.org/dk_poster.jpg", extension: "jpg"}
        ],
        identifier: %{property_id: "tmdb", value: "155"}
      },
      season: nil,
      extra: nil
    }

    Map.merge(defaults, Enum.into(overrides, %{}))
  end

  defp tv_metadata(overrides \\ %{}) do
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
        %{role: "poster", url: "https://image.tmdb.org/bb_poster.jpg", extension: "jpg"}
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
            %{role: "thumb", url: "https://image.tmdb.org/ep_thumb.jpg", extension: "jpg"}
          ]
        }
      },
      extra: nil
    }

    Map.merge(defaults, Enum.into(overrides, %{}))
  end

  defp payload_with(metadata, staged_images \\ []) do
    %Payload{metadata: metadata, staged_images: staged_images}
  end

  defp create_staged_image(staging_dir, owner, role) do
    filename = "#{owner}_#{role}.jpg"
    path = Path.join(staging_dir, filename)
    File.mkdir_p!(staging_dir)
    File.write!(path, "fake image bytes")
    %{role: role, owner: owner, local_path: path}
  end

  # ---------------------------------------------------------------------------
  # Standalone movie
  # ---------------------------------------------------------------------------

  describe "standalone movie" do
    test "creates entity, identifier, and images" do
      payload = payload_with(movie_metadata())

      assert {:ok, entity, :new} = Ingress.ingest(payload)

      assert entity.type == :movie
      assert entity.name == "Fight Club"
      assert entity.content_url == "/media/Fight.Club.1999.mkv"

      # Identifier created
      assert {:ok, [identifier]} = find_identifier("tmdb", "550")
      assert identifier.entity_id == entity.id

      # Images created
      entity = Ash.get!(Entity, entity.id, action: :with_images)
      assert length(entity.images) == 2
      assert Enum.any?(entity.images, &(&1.role == "poster"))
      assert Enum.any?(entity.images, &(&1.role == "backdrop"))
    end

    test "moves staged images to permanent storage", %{images_dir: images_dir} do
      staging_dir = Path.join(System.tmp_dir!(), "staging_#{Ash.UUID.generate()}")

      staged_images = [
        create_staged_image(staging_dir, "entity", "poster")
      ]

      metadata =
        movie_metadata(
          images: [
            %{role: "poster", url: "https://image.tmdb.org/poster.jpg", extension: "jpg"}
          ]
        )

      payload = payload_with(metadata, staged_images)

      assert {:ok, entity, :new} = Ingress.ingest(payload)

      # Image moved to permanent storage
      permanent_path = Path.join(images_dir, "#{entity.id}/poster.jpg")
      assert File.exists?(permanent_path)

      # Image record has content_url set
      entity = Ash.get!(Entity, entity.id, action: :with_images)
      poster = Enum.find(entity.images, &(&1.role == "poster"))
      assert poster.content_url == "#{entity.id}/poster.jpg"

      # Staging file no longer exists
      refute File.exists?(hd(staged_images).local_path)

      File.rm_rf!(staging_dir)
    end
  end

  # ---------------------------------------------------------------------------
  # Movie in collection
  # ---------------------------------------------------------------------------

  describe "movie in collection" do
    test "creates movie_series + child movie + identifiers + images" do
      payload = payload_with(collection_metadata())

      assert {:ok, entity, :new} = Ingress.ingest(payload)

      assert entity.type == :movie_series
      assert entity.name == "The Shadowy Sentinel Collection"

      # Collection identifier
      assert {:ok, [collection_id]} = find_identifier("tmdb_collection", "263")
      assert collection_id.entity_id == entity.id

      # Movie-level TMDB identifier
      assert {:ok, [movie_id]} = find_identifier("tmdb", "155")
      assert movie_id.entity_id == entity.id

      # Child movie
      entity = Ash.load!(entity, [:movies])
      assert length(entity.movies) == 1
      movie = hd(entity.movies)
      assert movie.name == "The Shadowy Sentinel"
      assert movie.content_url == "/media/The.Shadowy.Sentinel.2008.mkv"
      assert movie.position == 1
    end

    test "existing movie series — adds new child movie" do
      # Pre-create the series entity and collection identifier
      series = create_entity(%{type: :movie_series, name: "The Shadowy Sentinel Collection"})
      create_identifier(%{entity_id: series.id, property_id: "tmdb_collection", value: "263"})

      metadata =
        collection_metadata(
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

      payload = payload_with(metadata)

      assert {:ok, entity, :new_child} = Ingress.ingest(payload)
      assert entity.id == series.id

      entity = Ash.load!(entity, [:movies])
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
    test "creates entity, season, episode, and episode images" do
      payload = payload_with(tv_metadata())

      assert {:ok, entity, :new} = Ingress.ingest(payload)

      assert entity.type == :tv_series
      assert entity.name == "Sample Show Eight"

      # Identifier
      assert {:ok, [identifier]} = find_identifier("tmdb", "1396")
      assert identifier.entity_id == entity.id

      # Season + Episode
      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert length(entity.seasons) == 1
      season = hd(entity.seasons)
      assert season.season_number == 1
      assert length(season.episodes) == 1
      episode = hd(season.episodes)
      assert episode.episode_number == 1
      assert episode.name == "Pilot"
      assert episode.content_url == "/media/TV/Sample.Show.Eight.S01E01.mkv"
    end

    test "existing TV series — adds new episode to existing season" do
      existing = create_entity(%{type: :tv_series, name: "Sample Show Eight"})
      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "1396"})

      metadata =
        tv_metadata(
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

      payload = payload_with(metadata)

      assert {:ok, entity, :existing} = Ingress.ingest(payload)
      assert entity.id == existing.id

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert length(entity.seasons) == 1
      episode = hd(hd(entity.seasons).episodes)
      assert episode.episode_number == 2
      assert episode.content_url == "/media/TV/Sample.Show.Eight.S01E02.mkv"
    end

    test "TV without season/episode — no-op" do
      metadata = tv_metadata(season: nil)
      payload = payload_with(metadata)

      assert {:ok, entity, :new} = Ingress.ingest(payload)
      assert entity.type == :tv_series

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
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

      payload = payload_with(movie_metadata())

      assert {:ok, entity, :existing} = Ingress.ingest(payload)
      assert entity.id == existing.id

      reloaded = Ash.get!(Entity, entity.id)
      assert reloaded.content_url == "/media/Fight.Club.1999.mkv"
    end

    test "existing movie with content_url is returned unchanged" do
      existing =
        create_entity(%{type: :movie, name: "Fight Club", content_url: "/media/original.mkv"})

      create_identifier(%{entity_id: existing.id, property_id: "tmdb", value: "550"})

      payload = payload_with(movie_metadata())

      assert {:ok, entity, :existing} = Ingress.ingest(payload)
      assert entity.id == existing.id

      reloaded = Ash.get!(Entity, entity.id)
      assert reloaded.content_url == "/media/original.mkv"
    end
  end

  # ---------------------------------------------------------------------------
  # Extras
  # ---------------------------------------------------------------------------

  describe "extras" do
    test "extra without season — creates movie entity + extra" do
      metadata =
        movie_metadata(
          extra: %{
            name: "Behind the Scenes",
            content_url: "/media/extras/bts.mkv",
            season_number: nil
          }
        )

      payload = payload_with(metadata)

      assert {:ok, entity, :new} = Ingress.ingest(payload)
      assert entity.type == :movie

      # Entity should NOT get the extra's file path as content_url
      assert is_nil(entity.content_url)

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
      assert length(entity.extras) == 1
      extra = hd(entity.extras)
      assert extra.name == "Behind the Scenes"
      assert extra.content_url == "/media/extras/bts.mkv"
    end

    test "extra with season — creates TV entity + season + extra" do
      metadata =
        tv_metadata(
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

      payload = payload_with(metadata)

      assert {:ok, entity, :new} = Ingress.ingest(payload)
      assert entity.type == :tv_series

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
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

      metadata =
        movie_metadata(
          extra: %{
            name: "Deleted Scenes",
            content_url: "/media/extras/deleted.mkv",
            season_number: nil
          }
        )

      payload = payload_with(metadata)

      assert {:ok, entity, :existing} = Ingress.ingest(payload)
      assert entity.id == existing.id

      entity = Ash.get!(Entity, entity.id, action: :with_associations)
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

      payload = payload_with(movie_metadata())

      # The ingress will create a new entity, then when creating the identifier
      # it'll find the existing one belongs to winner. It destroys the duplicate
      # and returns the winner via link_to_existing.
      assert {:ok, entity, :existing} = Ingress.ingest(payload)
      assert entity.id == winner.id

      # The duplicate entity was destroyed — only the winner remains
      {:ok, entities} = Ash.read(Entity)
      assert length(entities) == 1
      assert hd(entities).id == winner.id
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "missing metadata raises" do
      payload = %Payload{metadata: nil, staged_images: []}

      assert_raise BadMapError, fn ->
        Ingress.ingest(payload)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp find_identifier(property_id, value) do
    query =
      case property_id do
        "tmdb_collection" ->
          Ash.Query.for_read(Identifier, :find_by_tmdb_collection, %{collection_id: value})

        _ ->
          Ash.Query.for_read(Identifier, :find_by_tmdb_id, %{tmdb_id: value})
      end

    Ash.read(query)
  end
end
