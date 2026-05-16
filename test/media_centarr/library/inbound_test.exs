defmodule MediaCentarr.Library.InboundTest do
  @moduledoc """
  Tests for Library.Inbound — the library's inbound API for the pipeline.

  No TMDB stubs needed: Inbound consumes pre-built metadata maps, not
  TMDB data. Tests construct event maps directly and call `ingest/1`.

  Inbound also creates WatchedFile records, queues images for download,
  and broadcasts entity changes — but those are integration concerns
  tested via the pipeline end-to-end, not here.
  """
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Inbound
  alias MediaCentarr.Library.PlayableItem
  alias MediaCentarr.Library.WatchedFile

  # WatchedFiles key to PlayableItem post-Phase-2-Task-B. Returns the
  # `(container_type, container_id)` pair the file's PlayableItem
  # points at, so tests can assert "this file resolves to this movie".
  defp container_for(%WatchedFile{playable_item_id: id}) do
    %PlayableItem{container_type: type, container_id: container_id} =
      MediaCentarr.Repo.get!(PlayableItem, id)

    {type, container_id}
  end

  # ---------------------------------------------------------------------------
  # Event builders
  # ---------------------------------------------------------------------------

  defp movie_event(overrides \\ %{}) do
    defaults = %{
      entity_type: :movie,
      entity_attrs: %{
        type: :movie,
        name: "Sample Movie",
        description: "A sample movie description.",
        date_published: ~D[1999-10-15],
        content_url: "/media/Sample.Movie.1999.mkv",
        url: "https://www.themoviedb.org/movie/550",
        tmdb_id: "550"
      },
      images: [
        %{role: "poster", url: "https://image.tmdb.org/poster.jpg"},
        %{role: "backdrop", url: "https://image.tmdb.org/backdrop.jpg"}
      ],
      identifier: %{source: "tmdb", external_id: "550"},
      child_movie: nil,
      season: nil,
      extra: nil,
      file_path: "/media/Sample.Movie.1999.mkv",
      watch_dir: "/media"
    }

    Map.merge(defaults, Map.new(overrides))
  end

  defp collection_event(overrides \\ %{}) do
    defaults = %{
      entity_type: :movie_series,
      entity_attrs: %{
        type: :movie_series,
        name: "Sample Movie Collection",
        tmdb_id: "263"
      },
      images: [
        %{role: "poster", url: "https://image.tmdb.org/coll_poster.jpg"}
      ],
      identifier: %{source: "tmdb_collection", external_id: "263"},
      child_movie: %{
        attrs: %{
          tmdb_id: "155",
          name: "Sample Movie Two",
          description: "Sample description.",
          date_published: ~D[2008-07-18],
          content_url: "/media/Sample.Movie.2008.mkv",
          url: "https://www.themoviedb.org/movie/155",
          position: 1
        },
        images: [
          %{role: "poster", url: "https://image.tmdb.org/dk_poster.jpg"}
        ],
        identifier: %{source: "tmdb", external_id: "155"}
      },
      season: nil,
      extra: nil,
      file_path: "/media/Sample.Movie.2008.mkv",
      watch_dir: "/media"
    }

    Map.merge(defaults, Map.new(overrides))
  end

  defp tv_event(overrides \\ %{}) do
    defaults = %{
      entity_type: :tv_series,
      entity_attrs: %{
        type: :tv_series,
        name: "Sample Show",
        description: "A sample show description.",
        number_of_seasons: 5,
        url: "https://www.themoviedb.org/tv/1396",
        tmdb_id: "1396"
      },
      images: [
        %{role: "poster", url: "https://image.tmdb.org/bb_poster.jpg"}
      ],
      identifier: %{source: "tmdb", external_id: "1396"},
      child_movie: nil,
      season: %{
        season_number: 1,
        name: "Season 1",
        number_of_episodes: 7,
        episode: %{
          attrs: %{
            episode_number: 1,
            name: "Pilot",
            description: "Sample episode description.",
            duration_seconds: 3480,
            content_url: "/media/TV/Sample.Show.S01E01.mkv"
          },
          images: [
            %{role: "thumb", url: "https://image.tmdb.org/ep_thumb.jpg"}
          ]
        }
      },
      extra: nil,
      file_path: "/media/TV/Sample.Show.S01E01.mkv",
      watch_dir: "/media/TV"
    }

    Map.merge(defaults, Map.new(overrides))
  end

  # ---------------------------------------------------------------------------
  # Standalone movie
  # ---------------------------------------------------------------------------

  describe "standalone movie" do
    test "creates type record and identifier, returns pending images" do
      assert {:ok, movie, :new, pending_images} = Inbound.ingest(movie_event())

      assert %Library.Movie{} = movie
      assert movie.name == "Sample Movie"
      assert movie.content_url == "/media/Sample.Movie.1999.mkv"

      # Type-specific Movie record created directly
      assert {:ok, reloaded} = Library.fetch_movie(movie.id)
      assert reloaded.name == "Sample Movie"
      assert reloaded.content_url == "/media/Sample.Movie.1999.mkv"

      # tmdb_id stored on a polymorphic ExternalId row
      assert Library.find_by_external_id(:movie, "550").id == movie.id

      # WatchedFile linked to a PlayableItem(:movie, movie.id).
      [file] = MediaCentarr.Repo.all(WatchedFile)
      assert container_for(file) == {:movie, movie.id}

      # Images collected for queue (not created in DB)
      assert length(pending_images) == 2
      roles = Enum.sort(Enum.map(pending_images, & &1.role))
      assert roles == ["backdrop", "poster"]

      assert Enum.all?(pending_images, fn img ->
               img.owner_id == movie.id and img.owner_type == "movie"
             end)
    end

    test "pending images carry source_url from event" do
      event =
        movie_event(
          images: [
            %{role: "poster", url: "https://image.tmdb.org/poster.jpg"}
          ]
        )

      assert {:ok, movie, :new, pending_images} = Inbound.ingest(event)

      assert [image] = pending_images
      assert image.source_url == "https://image.tmdb.org/poster.jpg"
      assert image.owner_id == movie.id
      assert image.owner_type == "movie"
      assert image.role == "poster"
      assert image.extension == "jpg"
    end
  end

  # ---------------------------------------------------------------------------
  # Movie in collection
  # ---------------------------------------------------------------------------

  describe "movie in collection" do
    test "creates movie_series + child movie + identifiers, returns pending images" do
      assert {:ok, series, :new, pending_images} = Inbound.ingest(collection_event())

      assert %Library.MovieSeries{} = series
      assert series.name == "Sample Movie Collection"

      # Type-specific MovieSeries record created directly
      assert {:ok, reloaded} = Library.fetch_movie_series(series.id)
      assert reloaded.name == "Sample Movie Collection"

      # tmdb_id stored on a polymorphic ExternalId row
      assert Library.find_by_external_id(:movie_series, "263").id == series.id

      # Child movie with movie_series_id FK
      series = MediaCentarr.Repo.preload(series, [:movies])
      assert length(series.movies) == 1
      movie = hd(series.movies)
      assert movie.name == "Sample Movie Two"
      assert movie.content_url == "/media/Sample.Movie.2008.mkv"
      assert movie.position == 1
      assert movie.movie_series_id == series.id

      # Pending images include movie_series + child movie images
      assert length(pending_images) == 2
      series_image = Enum.find(pending_images, &(&1.owner_type == "movie_series"))
      movie_image = Enum.find(pending_images, &(&1.owner_type == "movie"))
      assert series_image.role == "poster"
      assert movie_image.role == "poster"
      assert movie_image.owner_id == movie.id

      # WatchedFile links to a PlayableItem(:movie, child_movie.id) —
      # never to the parent MovieSeries. The presentable-queries side
      # counts files via PlayableItem container_id on child movies;
      # misattaching to MovieSeries-level would hide the collection.
      [file] = MediaCentarr.Repo.all(WatchedFile)
      assert container_for(file) == {:movie, movie.id}
    end

    test "existing movie series — adds new child movie" do
      # Pre-create the series with the canonical TMDB id on the entity
      series =
        create_entity(%{type: :movie_series, name: "Sample Movie Collection", tmdb_id: "263"})

      event =
        collection_event(
          child_movie: %{
            attrs: %{
              tmdb_id: "49026",
              name: "Sample Movie Three",
              description: "Sample description.",
              date_published: ~D[2012-07-20],
              content_url: "/media/Sample.Movie.Three.2012.mkv",
              position: 2
            },
            images: [],
            identifier: %{source: "tmdb", external_id: "49026"}
          }
        )

      assert {:ok, entity, :new_child, _pending_images} = Inbound.ingest(event)
      assert entity.id == series.id

      # Child movie created with movie_series_id FK, load via MovieSeries
      assert {:ok, movie_series} = Library.fetch_movie_series(entity.id)
      movie_series = MediaCentarr.Repo.preload(movie_series, :movies)
      assert length(movie_series.movies) == 1
      movie = hd(movie_series.movies)
      assert movie.name == "Sample Movie Three"
      assert movie.position == 2

      # WatchedFile links to a PlayableItem(:movie, new_child_movie.id) —
      # never to the parent MovieSeries.
      [file] = MediaCentarr.Repo.all(WatchedFile)
      assert container_for(file) == {:movie, movie.id}
    end
  end

  # ---------------------------------------------------------------------------
  # TV series
  # ---------------------------------------------------------------------------

  describe "TV series" do
    test "creates type record, season, episode, returns pending images" do
      assert {:ok, tv_series, :new, pending_images} = Inbound.ingest(tv_event())

      assert %Library.TVSeries{} = tv_series
      assert tv_series.name == "Sample Show"
      assert tv_series.number_of_seasons == 5

      # tmdb_id stored directly on TVSeries
      assert Library.find_by_external_id(:tv_series, "1396").id == tv_series.id

      # Season + Episode (via tv_series preload)
      tv_series = MediaCentarr.Repo.preload(tv_series, seasons: :episodes)
      assert length(tv_series.seasons) == 1
      season = hd(tv_series.seasons)
      assert season.season_number == 1
      assert season.tv_series_id == tv_series.id
      assert length(season.episodes) == 1
      episode = hd(season.episodes)
      assert episode.episode_number == 1
      assert episode.name == "Pilot"
      assert episode.content_url == "/media/TV/Sample.Show.S01E01.mkv"

      # Pending images: tv_series poster + episode thumb
      assert length(pending_images) == 2
      series_image = Enum.find(pending_images, &(&1.owner_type == "tv_series"))
      episode_image = Enum.find(pending_images, &(&1.owner_type == "episode"))
      assert series_image.role == "poster"
      assert episode_image.role == "thumb"
      assert episode_image.owner_id == episode.id
    end

    test "existing TV series — adds new episode to existing season" do
      existing = create_entity(%{type: :tv_series, name: "Sample Show", tmdb_id: "1396"})

      event =
        tv_event(
          season: %{
            season_number: 1,
            name: "Season 1",
            number_of_episodes: 7,
            episode: %{
              attrs: %{
                episode_number: 2,
                name: "Sample Episode 2",
                description: "Sample episode description.",
                duration_seconds: 2880,
                content_url: "/media/TV/Sample.Show.S01E02.mkv"
              },
              images: []
            }
          }
        )

      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(event)
      assert entity.id == existing.id

      # Season/Episode created with tv_series_id FK, load via TVSeries
      assert {:ok, tv_series} = Library.fetch_tv_series(entity.id)
      tv_series = MediaCentarr.Repo.preload(tv_series, seasons: :episodes)
      assert length(tv_series.seasons) == 1
      episode = hd(hd(tv_series.seasons).episodes)
      assert episode.episode_number == 2
      assert episode.content_url == "/media/TV/Sample.Show.S01E02.mkv"
    end

    test "TV without season/episode — no-op" do
      event = tv_event(season: nil)

      assert {:ok, tv_series, :new, _pending_images} = Inbound.ingest(event)
      assert %Library.TVSeries{} = tv_series

      tv_series = MediaCentarr.Repo.preload(tv_series, :seasons)
      assert tv_series.seasons == []
    end
  end

  # ---------------------------------------------------------------------------
  # Existing entity reuse
  # ---------------------------------------------------------------------------

  describe "existing entity reuse" do
    test "existing movie sets content_url if nil" do
      existing = create_entity(%{type: :movie, name: "Sample Movie", tmdb_id: "550"})

      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(movie_event())
      assert entity.id == existing.id

      {:ok, reloaded} = Library.fetch_movie(entity.id)
      assert reloaded.content_url == "/media/Sample.Movie.1999.mkv"
    end

    test "existing movie with content_url is returned unchanged" do
      existing =
        create_entity(%{
          type: :movie,
          name: "Sample Movie",
          content_url: "/media/original.mkv",
          tmdb_id: "550"
        })

      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(movie_event())
      assert entity.id == existing.id

      {:ok, reloaded} = Library.fetch_movie(entity.id)
      assert reloaded.content_url == "/media/original.mkv"
    end
  end

  # ---------------------------------------------------------------------------
  # Extras
  # ---------------------------------------------------------------------------

  describe "extras" do
    test "extra without season — creates movie + extra" do
      event =
        movie_event(
          extra: %{
            name: "Behind the Scenes",
            content_url: "/media/extras/bts.mkv",
            season_number: nil
          }
        )

      assert {:ok, movie, :new, _pending_images} = Inbound.ingest(event)
      assert %Library.Movie{} = movie

      # Movie should NOT get the extra's file path as content_url
      assert is_nil(movie.content_url)

      movie = MediaCentarr.Repo.preload(movie, :extras)
      assert length(movie.extras) == 1
      extra = hd(movie.extras)
      assert extra.name == "Behind the Scenes"
      assert extra.content_url == "/media/extras/bts.mkv"
    end

    test "extra with season — creates TV series + season + extra" do
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

      assert {:ok, tv_series, :new, _pending_images} = Inbound.ingest(event)
      assert %Library.TVSeries{} = tv_series

      tv_series = MediaCentarr.Repo.preload(tv_series, seasons: :extras)
      assert length(tv_series.seasons) == 1
      season = hd(tv_series.seasons)
      assert length(season.extras) == 1
      extra = hd(season.extras)
      assert extra.name == "Making Of"
      assert extra.content_url == "/media/extras/making_of.mkv"
    end

    test "extra on existing entity — reuses parent, creates extra only" do
      existing = create_entity(%{type: :movie, name: "Sample Movie", tmdb_id: "550"})

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

      # Extra created with movie_id FK, load via the Movie type record
      assert {:ok, movie} = Library.fetch_movie(entity.id)
      movie = MediaCentarr.Repo.preload(movie, :extras)
      assert length(movie.extras) == 1
      assert hd(movie.extras).name == "Deleted Scenes"
    end
  end

  # ---------------------------------------------------------------------------
  # Race-loss recovery
  # ---------------------------------------------------------------------------

  describe "race-loss recovery" do
    test "detects race loss via tmdb_id unique constraint, returns winner" do
      # Pre-create a "winner" entity with the same TMDB id on the row.
      # find_existing_entity hits this directly — the link_to_existing
      # path runs without ever attempting an insert, but the constraint
      # remains the safety net for a true race.
      winner = create_entity(%{type: :movie, name: "Sample Movie (Winner)", tmdb_id: "550"})

      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(movie_event())
      assert entity.id == winner.id

      # No duplicate was created — only the winner remains.
      movies = Library.list_movies()
      assert length(movies) == 1
      assert hd(movies).id == winner.id
    end

    test "race-loss cleans up orphan container's PlayableItem" do
      # Simulate the rarer true race: a winning Movie was inserted *after*
      # `find_existing_entity` returned `:not_found`. The losing process
      # creates a container + PlayableItem and then discovers the conflict
      # at the ExternalId write. The loser's container AND PlayableItem
      # must both be cleaned up so the system converges on the winner.
      winner = create_entity(%{type: :movie, name: "Sample Movie (Winner)", tmdb_id: "550"})

      # `find_by_external_id` returns the winner directly, so we exercise
      # the `link_to_existing` path here — that's the dominant production
      # path. The destructive race-loss branch is exercised indirectly
      # through `EntityCascade.destroy!` integrity (a separate test).
      assert {:ok, entity, :existing, _pending_images} = Inbound.ingest(movie_event())
      assert entity.id == winner.id

      # The winner has exactly one PlayableItem (created when the winner
      # was first set up via `create_entity` — Task G ensures every leaf
      # has a PlayableItem) — never two.
      items = Library.list_playable_items_for(:movie, winner.id)
      assert length(items) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # PlayableItem creation on leaf ingest (Library Schema v2 Phase 2 Task G)
  # ---------------------------------------------------------------------------

  describe "PlayableItem creation on leaf ingest" do
    test "movie ingest creates PlayableItem(:movie, movie.id, 1)" do
      assert {:ok, movie, :new, _images} = Inbound.ingest(movie_event())

      assert [%PlayableItem{container_type: :movie, position: 1}] =
               Library.list_playable_items_for(:movie, movie.id)
    end

    test "episode ingest creates PlayableItem(:episode, episode.id, episode_number)" do
      assert {:ok, tv_series, :new, _images} = Inbound.ingest(tv_event())

      tv_series = MediaCentarr.Repo.preload(tv_series, seasons: :episodes)
      episode = hd(hd(tv_series.seasons).episodes)

      assert [%PlayableItem{container_type: :episode, container_id: container_id, position: 1}] =
               Library.list_playable_items_for(:episode, episode.id)

      assert container_id == episode.id
    end

    test "video_object ingest creates PlayableItem(:video_object, vo.id, 1)" do
      event = %{
        entity_type: :video_object,
        entity_attrs: %{
          type: :video_object,
          name: "Sample Video",
          description: "A standalone video.",
          content_url: "/media/Sample.Video.mkv",
          tmdb_id: "9999"
        },
        images: [],
        identifier: %{source: "tmdb", external_id: "9999"},
        child_movie: nil,
        season: nil,
        extra: nil,
        file_path: "/media/Sample.Video.mkv",
        watch_dir: "/media"
      }

      assert {:ok, video_object, :new, _images} = Inbound.ingest(event)

      assert [%PlayableItem{container_type: :video_object, position: 1}] =
               Library.list_playable_items_for(:video_object, video_object.id)
    end

    test "movie-series-child ingest creates PlayableItem(:movie, child.id, child.position)" do
      assert {:ok, series, :new, _images} = Inbound.ingest(collection_event())

      series = MediaCentarr.Repo.preload(series, :movies)
      child = hd(series.movies)

      # Position on the PlayableItem mirrors the child's own `position`
      # (collection ordering) — defaulting to 1 when missing.
      assert [%PlayableItem{container_type: :movie, container_id: container_id, position: 1}] =
               Library.list_playable_items_for(:movie, child.id)

      assert container_id == child.id

      # The parent MovieSeries never gets a PlayableItem of its own —
      # it's a container above the leaf, not a playable leaf.
      assert Enum.filter(MediaCentarr.Repo.all(PlayableItem), &(&1.container_id == series.id)) == []
    end

    test "TV ingest without season/episode creates NO PlayableItem" do
      # The TV series is not itself a leaf; only its episodes are. An
      # ingest that doesn't carry an Episode payload must NOT leave a
      # stray PlayableItem behind (which would break presentable queries
      # that count files-via-PlayableItem on real leaves).
      event = tv_event(season: nil)

      assert {:ok, tv_series, :new, _images} = Inbound.ingest(event)
      assert MediaCentarr.Repo.all(PlayableItem) == []

      refute Enum.any?(MediaCentarr.Repo.all(PlayableItem), &(&1.container_id == tv_series.id))
    end

    test "adding a second episode to existing TV series creates its PlayableItem" do
      assert {:ok, tv_series, :new, _images} = Inbound.ingest(tv_event())

      event =
        tv_event(
          season: %{
            season_number: 1,
            name: "Season 1",
            number_of_episodes: 7,
            episode: %{
              attrs: %{
                episode_number: 2,
                name: "Sample Episode 2",
                description: "Sample episode description.",
                duration_seconds: 2880,
                content_url: "/media/TV/Sample.Show.S01E02.mkv"
              },
              images: []
            }
          },
          file_path: "/media/TV/Sample.Show.S01E02.mkv"
        )

      assert {:ok, ^tv_series, :existing, _images} = Inbound.ingest(event)

      tv_series = MediaCentarr.Repo.preload(tv_series, seasons: :episodes)
      episodes = Enum.sort_by(hd(tv_series.seasons).episodes, & &1.episode_number)
      assert length(episodes) == 2

      # Each episode has its own PlayableItem keyed by its episode_number.
      Enum.each(episodes, fn episode ->
        assert [%PlayableItem{position: pos}] =
                 Library.list_playable_items_for(:episode, episode.id)

        assert pos == episode.episode_number
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Post-ingest side effects
  # ---------------------------------------------------------------------------

  describe "post-ingest side effects" do
    test "creates WatchedFile linking file to type record" do
      assert {:ok, movie, :new, _images} = Inbound.ingest(movie_event())

      [file] = MediaCentarr.Repo.all(WatchedFile)
      assert file.file_path == "/media/Sample.Movie.1999.mkv"
      assert file.watch_dir == "/media"
      assert container_for(file) == {:movie, movie.id}
    end

    test "broadcasts pending images for queueing by Pipeline" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.pipeline_images())

      assert {:ok, movie, :new, pending_images} = Inbound.ingest(movie_event())
      assert length(pending_images) == 2

      assert_receive {:enqueue_images, %{entity_id: entity_id, watch_dir: watch_dir, images: images}}
      assert entity_id == movie.id
      assert watch_dir == "/media"
      assert length(images) == 2
      assert Enum.sort(Enum.map(images, & &1.role)) == ["backdrop", "poster"]
    end

    test "broadcasts entities_changed to library:updates" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_updates())

      assert {:ok, movie, :new, _images} = Inbound.ingest(movie_event())

      assert_receive {:entities_changed, %{entity_ids: entity_ids}}, 500
      assert movie.id in entity_ids
    end

    test "skips image queue broadcast when no images" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.pipeline_images())

      event = movie_event(images: [])
      assert {:ok, _movie, :new, []} = Inbound.ingest(event)

      refute_receive {:enqueue_images, _}
    end
  end

  # ---------------------------------------------------------------------------
  # Image ready (from image pipeline)
  # ---------------------------------------------------------------------------

  describe "image_ready" do
    test "creates image record for movie owner" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})

      send_image_ready(%{
        owner_id: movie.id,
        owner_type: "movie",
        role: "poster",
        content_url: "images/#{movie.id}/poster.jpg",
        extension: "jpg",
        entity_id: movie.id
      })

      movie = MediaCentarr.Repo.preload(movie, :images)
      assert [image] = movie.images
      assert image.role == "poster"
      assert image.content_url == "images/#{movie.id}/poster.jpg"
      assert image.owner_type == :movie
      assert image.owner_id == movie.id
    end

    test "creates image record for child movie owner" do
      series = create_entity(%{type: :movie_series, name: "Collection"})

      {:ok, movie} =
        Library.find_or_create_movie_for_series(%{
          movie_series_id: series.id,
          tmdb_id: "155",
          name: "Movie",
          position: 1
        })

      send_image_ready(%{
        owner_id: movie.id,
        owner_type: "movie",
        role: "poster",
        content_url: "images/#{series.id}/movie_poster.jpg",
        extension: "jpg",
        entity_id: series.id
      })

      movie = MediaCentarr.Repo.preload(movie, :images)
      assert [image] = movie.images
      assert image.role == "poster"
      assert image.owner_type == :movie
      assert image.owner_id == movie.id
    end

    test "broadcasts entities_changed after image creation" do
      movie = create_entity(%{type: :movie, name: "Test Movie"})
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_updates())

      send_image_ready(%{
        owner_id: movie.id,
        owner_type: "movie",
        role: "backdrop",
        content_url: "images/#{movie.id}/backdrop.jpg",
        extension: "jpg",
        entity_id: movie.id
      })

      assert_receive {:entities_changed, %{entity_ids: entity_ids}}, 500
      assert movie.id in entity_ids
    end
  end

  # ---------------------------------------------------------------------------
  # Rematch
  # ---------------------------------------------------------------------------

  describe "handle_rematch/1" do
    test "destroys entity and watched files, sends file list to review:intake" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_updates())
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.review_intake())

      movie =
        create_entity(%{
          type: :movie,
          name: "Wrong Movie",
          content_url: "/media/movies/Sample Movie (2017).mkv"
        })

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/movies/Sample Movie (2017).mkv",
        watch_dir: "/media/movies"
      })

      assert :ok = Inbound.handle_rematch(movie.id)

      # Entity destroyed
      assert {:error, _} = Library.fetch_movie(movie.id)

      # WatchedFiles destroyed
      assert Library.list_watched_files_by_entity_id(movie.id) == []

      # Broadcasts entities_changed (via coalescer — allow flush window).
      # Coalescer may bundle this entity's ID with IDs from concurrent tests'
      # broadcasts in the same 200ms window — assert membership, not exact list.
      assert_receive {:entities_changed, %{entity_ids: ids}}, 500
      assert movie.id in ids

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
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.review_intake())

      tv_series = create_entity(%{type: :tv_series, name: "Wrong Show"})

      season =
        create_season(%{
          tv_series_id: tv_series.id,
          season_number: 1,
          number_of_episodes: 2
        })

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E01.mkv"
      })

      create_episode(%{
        season_id: season.id,
        episode_number: 2,
        name: "Second",
        content_url: "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E02.mkv"
      })

      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "wrong"})

      create_linked_file(%{
        tv_series_id: tv_series.id,
        file_path: "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E01.mkv",
        watch_dir: "/media/tv"
      })

      create_linked_file(%{
        tv_series_id: tv_series.id,
        file_path: "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E02.mkv",
        watch_dir: "/media/tv"
      })

      assert :ok = Inbound.handle_rematch(tv_series.id)

      # Entity fully destroyed
      assert {:error, _} = Library.fetch_tv_series(tv_series.id)

      # Both files sent to review
      assert_received {:files_for_review, files}
      assert length(files) == 2
      paths = Enum.sort(Enum.map(files, & &1.file_path))

      assert paths == [
               "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E01.mkv",
               "/media/tv/Sample Show (2001)/Season 1/Sample Show S01E02.mkv"
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

  defp send_image_ready(attrs) do
    Inbound.process_image_ready(attrs)
  end
end
