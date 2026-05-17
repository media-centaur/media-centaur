defmodule MediaCentarr.TestFactory do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Shared test data builders.

  - `build_*` functions return structs or maps with sensible defaults (no DB).
    Use for pure-function tests (Serializer, Mapper, ProgressSummary, etc.).
    Note: `build_entity` returns a plain map (normalized entity shape);
    `build_tv_series`, `build_movie_series`, etc. return Ecto structs.
  - `create_*` functions persist via context functions and return loaded records.
    Use for resource tests and channel tests.
  """

  alias MediaCentarr.Library

  alias MediaCentarr.Library.{
    Extra,
    Image,
    ExternalId,
    Movie,
    MovieSeries,
    Person,
    PlayableItem,
    Season,
    Episode,
    TVSeries,
    VideoObject
  }

  alias MediaCentarr.Review

  # ---------------------------------------------------------------------------
  # build_* — plain structs, no database
  # ---------------------------------------------------------------------------

  def build_entity(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      type: :movie,
      name: "Test Movie",
      description: nil,
      date_published: nil,
      genres: nil,
      content_url: nil,
      url: nil,
      duration_seconds: nil,
      director: nil,
      content_rating: nil,
      number_of_seasons: nil,
      aggregate_rating_value: nil,
      vote_count: nil,
      tagline: nil,
      original_language: nil,
      studio: nil,
      country_code: nil,
      network: nil,
      status: nil,
      cast: [],
      crew: [],
      imdb_id: nil,
      images: [],
      external_ids: [],
      movies: [],
      extras: [],
      seasons: [],
      watched_files: [],
      watch_progress: [],
      extra_progress: []
    }

    Map.merge(defaults, overrides)
  end

  def build_image(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      role: "poster",
      content_url: nil,
      extension: "jpg",
      owner_type: nil,
      owner_id: nil
    }

    struct(Image, Map.merge(defaults, translate_owner_keys(overrides, :image)))
  end

  def build_external_id(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      source: "tmdb",
      external_id: "12345",
      owner_type: nil,
      owner_id: nil
    }

    struct(ExternalId, Map.merge(defaults, translate_owner_keys(overrides, :external_id)))
  end

  @doc """
  Builds a `MediaCentarr.Library.Person` embedded struct — used for
  cast and crew fixtures on `Movie` and `TVSeries`. Defaults to a
  cast-shaped entry (with `character` + `order`); pass `job` and
  `department` in overrides for crew-shaped entries.
  """
  def build_person(overrides \\ %{}) do
    defaults = %{
      name: "Sample Person",
      character: nil,
      order: nil,
      job: nil,
      department: nil,
      profile_path: nil,
      tmdb_person_id: nil
    }

    struct(Person, Map.merge(defaults, overrides))
  end

  def build_movie(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Child Movie",
      description: nil,
      date_published: nil,
      duration_seconds: nil,
      director: nil,
      content_rating: nil,
      content_url: nil,
      url: nil,
      aggregate_rating_value: nil,
      position: 0,
      status: nil,
      cast: [],
      crew: [],
      images: []
    }

    struct(Movie, Map.merge(defaults, overrides))
  end

  def build_extra(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Behind the Scenes",
      content_url: "/path/to/extra.mkv",
      position: 0,
      owner_type: nil,
      owner_id: nil
    }

    struct(Extra, Map.merge(defaults, translate_owner_keys(overrides, :extra)))
  end

  def build_season(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      season_number: 1,
      number_of_episodes: 0,
      name: "Season 1",
      episodes: [],
      extras: []
    }

    struct(Season, Map.merge(defaults, overrides))
  end

  def build_episode(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      episode_number: 1,
      name: "Pilot",
      description: nil,
      duration_seconds: nil,
      content_url: nil,
      season_id: nil,
      images: []
    }

    struct(Episode, Map.merge(defaults, overrides))
  end

  def build_progress(overrides \\ %{}) do
    overrides = Map.new(overrides)

    # Backward-compatible legacy FK keys. Pure-function tests still pass
    # `:movie_id` / `:episode_id` / `:video_object_id` because that's
    # how progress is conceptually identified. We synthesise the
    # `:playable_item` field (same shape `EntityShape.attach_container/3`
    # uses at runtime) so pure helpers can read the container id back.
    {container_type, container_id, overrides} =
      cond do
        movie_id = overrides[:movie_id] ->
          {:movie, movie_id, Map.delete(overrides, :movie_id)}

        episode_id = overrides[:episode_id] ->
          {:episode, episode_id, Map.delete(overrides, :episode_id)}

        video_object_id = overrides[:video_object_id] ->
          {:video_object, video_object_id, Map.delete(overrides, :video_object_id)}

        true ->
          {nil, nil, overrides}
      end

    playable_item =
      cond do
        Map.has_key?(overrides, :playable_item) ->
          overrides[:playable_item]

        container_id != nil ->
          %{container_type: container_type, container_id: container_id}

        true ->
          nil
      end

    # Pure-function tests use the legacy FK key as the conceptual identity
    # of the progress record. Since `LibraryProgress.merge_progress_record/2`
    # keys solely on `:playable_item_id` (Phase 2 Task C), fall back to the
    # legacy id when no `:playable_item_id` was passed so each record retains
    # a stable, unique key.
    playable_item_id =
      overrides[:playable_item_id] || container_id

    defaults = %{
      playable_item_id: playable_item_id,
      playable_item: playable_item,
      position_seconds: 0.0,
      duration_seconds: 0.0,
      completed: false,
      last_watched_at: DateTime.utc_now()
    }

    Map.merge(defaults, Map.delete(overrides, :playable_item))
  end

  def build_tv_series(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test TV Series",
      description: nil,
      date_published: nil,
      genres: nil,
      url: nil,
      aggregate_rating_value: nil,
      number_of_seasons: nil,
      status: nil,
      seasons: [],
      images: [],
      extras: [],
      external_ids: [],
      watched_files: []
    }

    struct(TVSeries, Map.merge(defaults, overrides))
  end

  def build_movie_series(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Movie Series",
      description: nil,
      date_published: nil,
      genres: nil,
      url: nil,
      aggregate_rating_value: nil,
      vote_count: nil,
      tagline: nil,
      original_language: nil,
      studio: nil,
      country_code: nil,
      status: nil,
      cast: [],
      crew: [],
      movies: [],
      images: [],
      extras: [],
      external_ids: [],
      watched_files: []
    }

    struct(MovieSeries, Map.merge(defaults, overrides))
  end

  def build_video_object(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Video",
      description: nil,
      date_published: nil,
      content_url: nil,
      url: nil,
      images: [],
      external_ids: [],
      watched_files: [],
      watch_progress: nil
    }

    struct(VideoObject, Map.merge(defaults, overrides))
  end

  def build_playable_item(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      container_type: :movie,
      container_id: Ecto.UUID.generate(),
      position: 1,
      duration_seconds: nil,
      name: nil
    }

    struct(PlayableItem, Map.merge(defaults, overrides))
  end

  def build_standalone_movie(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Standalone Movie",
      description: nil,
      date_published: nil,
      duration_seconds: nil,
      director: nil,
      content_rating: nil,
      content_url: nil,
      url: nil,
      aggregate_rating_value: nil,
      genres: nil,
      position: 0,
      status: nil,
      movie_series_id: nil,
      cast: [],
      crew: [],
      images: [],
      extras: [],
      external_ids: [],
      watched_files: [],
      watch_progress: nil
    }

    struct(Movie, Map.merge(defaults, overrides))
  end

  def build_parser_result(overrides \\ %{}) do
    defaults = %{
      file_path: "/media/Sample.Movie.1999.mkv",
      title: "Sample Movie",
      year: 1999,
      type: :movie,
      season: nil,
      episode: nil,
      episode_title: nil,
      parent_title: nil,
      parent_year: nil
    }

    struct(MediaCentarr.Parser.Result, Map.merge(defaults, overrides))
  end

  # ---------------------------------------------------------------------------
  # create_* — persisted via context functions, returns loaded records
  # ---------------------------------------------------------------------------

  def create_entity(attrs \\ %{}) do
    type = attrs[:type] || :movie
    defaults = %{name: "Test Movie"}
    tmdb_id = attrs[:tmdb_id]
    imdb_id = attrs[:imdb_id]
    content_url = attrs[:content_url]

    merged = Map.merge(defaults, Map.drop(attrs, [:type, :tmdb_id, :imdb_id, :content_url]))

    record =
      case type do
        :movie -> Library.create_movie!(merged)
        :tv_series -> Library.create_tv_series!(merged)
        :movie_series -> Library.create_movie_series!(merged)
        :video_object -> Library.create_video_object!(merged)
      end

    # TMDB / IMDB ids now live on `library_external_ids` rows
    # (Library Schema v2 Phase 1 Task 6). Forward any test-supplied
    # `tmdb_id` / `imdb_id` through `ExternalIds.put/3` so existing
    # test fixtures keep working without explicit `external_id`
    # plumbing.
    tmdb_source = if type == :movie_series, do: :tmdb_collection, else: :tmdb
    _ = Library.ExternalIds.put(tmdb_source, record, tmdb_id)
    _ = Library.ExternalIds.put(:imdb, record, imdb_id)

    # `Movie.content_url` / `VideoObject.content_url` are virtual after
    # Library Schema v2 Phase 2 Task I. Legacy fixtures still pass
    # `content_url: "/path/to/file"` as shorthand for "make this entity
    # playable" — translate it into a present WatchedFile so the
    # downstream resolvers and the virtual field both behave as before.
    record = link_factory_content_url(record, type, content_url)

    record
  end

  defp link_factory_content_url(record, _type, nil), do: record
  defp link_factory_content_url(record, :movie_series, _url), do: record
  defp link_factory_content_url(record, :tv_series, _url), do: record

  defp link_factory_content_url(record, :movie, url) when is_binary(url) do
    do_link_factory_content_url(record, :movie, url, record.position || 1)
  end

  defp link_factory_content_url(record, :video_object, url) when is_binary(url) do
    do_link_factory_content_url(record, :video_object, url, 1)
  end

  defp do_link_factory_content_url(record, container_type, url, position) do
    {:ok, playable_item} =
      Library.find_or_create_playable_item(container_type, record.id, position)

    Library.link_file!(%{
      playable_item_id: playable_item.id,
      file_path: url,
      watch_dir: "/media/test"
    })

    %{record | content_url: url}
  end

  def create_image(attrs) do
    attrs |> Map.new() |> translate_owner_keys(:image) |> Library.create_image!()
  end

  def create_external_id(attrs) do
    attrs |> Map.new() |> translate_owner_keys(:external_id) |> Library.create_external_id!()
  end

  def create_season(attrs) do
    Library.create_season!(attrs)
  end

  def create_episode(attrs) do
    attrs = Map.new(attrs)
    content_url = attrs[:content_url]
    clean_attrs = Map.delete(attrs, :content_url)
    episode = Library.create_episode!(clean_attrs)
    link_factory_content_url_for_episode(episode, content_url)
  end

  def create_movie(attrs) do
    create_with_external_ids(:movie, %{}, attrs, &Library.create_movie!/1)
  end

  def create_tv_series(attrs \\ %{}) do
    create_with_external_ids(:tv_series, %{name: "Test TV Series"}, attrs, &Library.create_tv_series!/1)
  end

  def create_movie_series(attrs \\ %{}) do
    create_with_external_ids(
      :movie_series,
      %{name: "Test Movie Series"},
      attrs,
      &Library.create_movie_series!/1
    )
  end

  def create_video_object(attrs \\ %{}) do
    create_with_external_ids(
      :video_object,
      %{name: "Test Video"},
      attrs,
      &Library.create_video_object!/1
    )
  end

  # Routes test-supplied `tmdb_id` / `imdb_id` through `ExternalIds.put/3`
  # rather than the container changeset (Library Schema v2 Phase 1 Task 6
  # moved both off the container columns and into ExternalId rows).
  # Also translates the legacy `content_url:` shorthand into a present
  # WatchedFile so callers' `record.content_url` reads keep working after
  # Library Schema v2 Phase 2 Task I dropped the persisted column.
  defp create_with_external_ids(type, defaults, attrs, creator) do
    attrs = Map.new(attrs)
    tmdb_id = attrs[:tmdb_id]
    imdb_id = attrs[:imdb_id]
    content_url = attrs[:content_url]
    clean_attrs = defaults |> Map.merge(attrs) |> Map.drop([:tmdb_id, :imdb_id, :content_url])

    record = creator.(clean_attrs)
    tmdb_source = if type == :movie_series, do: :tmdb_collection, else: :tmdb
    _ = Library.ExternalIds.put(tmdb_source, record, tmdb_id)
    _ = Library.ExternalIds.put(:imdb, record, imdb_id)
    link_factory_content_url(record, type, content_url)
  end

  def create_standalone_movie(attrs \\ %{}) do
    attrs = Map.new(attrs)
    defaults = %{name: "Test Standalone Movie", position: 0}
    tmdb_id = attrs[:tmdb_id]
    imdb_id = attrs[:imdb_id]
    content_url = attrs[:content_url]

    movie_attrs =
      defaults |> Map.merge(attrs) |> Map.drop([:tmdb_id, :imdb_id, :content_url])

    record = Library.create_movie!(movie_attrs)
    _ = Library.ExternalIds.put(:tmdb, record, tmdb_id)
    _ = Library.ExternalIds.put(:imdb, record, imdb_id)
    link_factory_content_url(record, :movie, content_url)
  end

  defp link_factory_content_url_for_episode(episode, nil), do: episode

  defp link_factory_content_url_for_episode(episode, url) when is_binary(url) do
    do_link_factory_content_url(episode, :episode, url, episode.episode_number || 1)
  end

  def create_extra(attrs) do
    attrs |> Map.new() |> translate_owner_keys(:extra) |> Library.create_extra!()
  end

  @doc """
  Persists an `ExtraFile` row linking a path on disk to an Extra. Mirrors
  `create_linked_file/1` for the WatchedFile/PlayableItem side, but for
  bonus features.
  """
  def create_extra_file(attrs \\ %{}) do
    defaults = %{
      file_path: "/media/test/extras/#{Ecto.UUID.generate()}.mkv",
      watch_dir: "/media/test"
    }

    merged = Map.merge(defaults, Map.new(attrs))
    Library.create_extra_file!(merged)
  end

  @doc """
  Convenience helper: creates an `ExtraFile` linked to the given Extra
  struct. Defaults file_path to the Extra's `content_url` when set.
  """
  def create_extra_file_for_extra(%Extra{id: extra_id, content_url: content_url}, overrides \\ %{}) do
    defaults = %{
      extra_id: extra_id,
      file_path: content_url || "/media/test/extras/#{Ecto.UUID.generate()}.mkv",
      watch_dir: "/media/test"
    }

    create_extra_file(Map.merge(defaults, Map.new(overrides)))
  end

  @doc """
  Persists a `PlayableItem` row via `Library.create_playable_item!/1`. The
  caller supplies `:container_type` / `:container_id` pointing at an
  existing container; defaults fill in `:position` when unset.
  """
  def create_playable_item(attrs) do
    defaults = %{position: 1}
    Library.create_playable_item!(Map.merge(defaults, Map.new(attrs)))
  end

  @doc """
  Convenience helper: returns the canonical `PlayableItem` for the given
  movie struct, creating it idempotently if absent. The factory's auto
  `content_url` linkage (Library Schema v2 Phase 2 Task I) may have
  created the row already; this helper plays nicely with both flows.
  """
  def create_playable_item_for_movie(%Movie{id: movie_id, position: position}, overrides \\ %{}) do
    overrides = Map.new(overrides)
    position = overrides[:position] || position || 1
    find_or_create_factory_playable_item(:movie, movie_id, position)
  end

  @doc """
  Convenience helper: returns the canonical `PlayableItem` for the given
  episode struct, creating it idempotently if absent. Position defaults
  to the episode's `episode_number` (or 1 if not set).
  """
  def create_playable_item_for_episode(
        %Episode{id: episode_id, episode_number: episode_number},
        overrides \\ %{}
      ) do
    overrides = Map.new(overrides)
    position = overrides[:position] || episode_number || 1
    find_or_create_factory_playable_item(:episode, episode_id, position)
  end

  @doc """
  Convenience helper: returns the canonical `PlayableItem` for the given
  video-object struct, creating it idempotently if absent.
  """
  def create_playable_item_for_video_object(%VideoObject{id: video_object_id}, overrides \\ %{}) do
    overrides = Map.new(overrides)
    position = overrides[:position] || 1
    find_or_create_factory_playable_item(:video_object, video_object_id, position)
  end

  defp find_or_create_factory_playable_item(container_type, container_id, position) do
    {:ok, item} = Library.find_or_create_playable_item(container_type, container_id, position)
    item
  end

  def create_entity_with_associations(attrs \\ %{}) do
    type = attrs[:type] || :movie
    # `create_entity` writes TMDB / IMDB ExternalId rows from
    # `attrs[:tmdb_id] / attrs[:imdb_id]` if present. Ensure a TMDB row
    # exists by defaulting tmdb_id to "99999" when not supplied so the
    # legacy contract — "this factory ALWAYS attaches a TMDB external
    # id" — holds for callers that don't pass one explicitly.
    attrs_with_default_tmdb = Map.put_new(attrs, :tmdb_id, "99999")
    record = create_entity(attrs_with_default_tmdb)
    fk = type_fk(type)

    create_image(%{
      fk => record.id,
      role: "poster",
      content_url: "#{record.id}/poster.jpg",
      extension: "jpg"
    })

    # Reload with associations
    case type do
      :movie -> Library.get_movie_with_associations!(record.id)
      :tv_series -> Library.get_tv_series_with_associations!(record.id)
      :movie_series -> Library.get_movie_series_with_associations!(record.id)
      :video_object -> Library.get_video_object_with_associations!(record.id)
    end
  end

  defp type_fk(:movie), do: :movie_id
  defp type_fk(:tv_series), do: :tv_series_id
  defp type_fk(:movie_series), do: :movie_series_id
  defp type_fk(:video_object), do: :video_object_id

  @doc """
  Persists a `WatchedFile` linked to a `PlayableItem`. The factory
  accepts both the new direct API (`:playable_item_id` or `:playable_item`)
  and the legacy per-type FK keys (`:movie_id`, `:tv_series_id`,
  `:movie_series_id`, `:video_object_id`) — the legacy keys are
  translated to a PlayableItem on the fly so existing test setups keep
  working through the Library Schema v2 Phase 2 Task B refit:

    * `:movie_id` — ensures `PlayableItem(:movie, movie_id, 1)`.
    * `:video_object_id` — ensures `PlayableItem(:video_object, vo_id, 1)`.
    * `:tv_series_id` — auto-creates a Season + Episode under the series
      whose `content_url == file_path`, then a `PlayableItem(:episode, …)`.
    * `:movie_series_id` — auto-creates a child Movie under the series
      whose `content_url == file_path`, then a `PlayableItem(:movie, …)`.
  """
  def create_linked_file(attrs \\ %{}) do
    defaults = %{
      file_path: "/media/test/#{Ecto.UUID.generate()}.mkv",
      watch_dir: "/media/test"
    }

    merged = Map.merge(defaults, Map.new(attrs))

    playable_item_id = resolve_playable_item_id_for_factory(merged)

    Library.link_file!(%{
      file_path: merged.file_path,
      watch_dir: merged.watch_dir,
      playable_item_id: playable_item_id
    })
  end

  # Translates the factory's legacy-shape attrs into a PlayableItem id.
  defp resolve_playable_item_id_for_factory(%{playable_item_id: id}) when is_binary(id), do: id

  defp resolve_playable_item_id_for_factory(%{playable_item: %{id: id}}), do: id

  defp resolve_playable_item_id_for_factory(%{movie_id: movie_id} = _attrs) when is_binary(movie_id) do
    ensure_factory_playable_item(:movie, movie_id, 1)
  end

  defp resolve_playable_item_id_for_factory(%{video_object_id: video_object_id})
       when is_binary(video_object_id) do
    ensure_factory_playable_item(:video_object, video_object_id, 1)
  end

  defp resolve_playable_item_id_for_factory(%{tv_series_id: tv_series_id, file_path: file_path})
       when is_binary(tv_series_id) do
    # Re-use an Episode under this series already linked to the file
    # path via its `PlayableItem → WatchedFile` chain; create one when
    # none exists. The shape parallels production Inbound — the leaf
    # Episode is the PlayableItem container. After Library Schema v2
    # Phase 2 Task I `Episode.content_url` no longer exists; the link
    # is recorded only on the WatchedFile.
    episode =
      Library.find_episode_by_path(tv_series_id, file_path) ||
        create_factory_episode_for_tv_series(tv_series_id)

    ensure_factory_playable_item(:episode, episode.id, episode.episode_number || 1)
  end

  defp resolve_playable_item_id_for_factory(%{movie_series_id: movie_series_id, file_path: file_path})
       when is_binary(movie_series_id) do
    movie =
      Library.find_movie_by_path(movie_series_id, file_path) ||
        create_factory_movie_for_series(movie_series_id)

    ensure_factory_playable_item(:movie, movie.id, movie.position || 1)
  end

  # Factory-created Episodes use a synthetic season number (9001) and
  # episode_number that won't collide with any explicit episode the
  # test creates afterwards. Each factory WatchedFile gets a fresh
  # episode_number so multiple calls don't share one episode.
  defp create_factory_episode_for_tv_series(tv_series_id) do
    {:ok, season} =
      Library.find_or_create_season_for_tv_series(%{
        tv_series_id: tv_series_id,
        season_number: 9001,
        name: "Factory Season",
        number_of_episodes: 0
      })

    episode_number = System.unique_integer([:positive]) + 9000

    {:ok, episode} =
      Library.find_or_create_episode(%{
        season_id: season.id,
        episode_number: episode_number,
        name: "Factory Episode"
      })

    episode
  end

  defp create_factory_movie_for_series(movie_series_id) do
    {:ok, movie} =
      Library.create_movie(%{
        name: "Factory Child Movie #{System.unique_integer([:positive])}",
        movie_series_id: movie_series_id,
        position: 1
      })

    movie
  end

  defp ensure_factory_playable_item(container_type, container_id, position) do
    case Library.create_playable_item(%{
           container_type: container_type,
           container_id: container_id,
           position: position
         }) do
      {:ok, item} ->
        item.id

      {:error, %Ecto.Changeset{}} ->
        [item | _] = Library.list_playable_items_for(container_type, container_id)
        item.id
    end
  end

  def create_pending_file(attrs \\ %{}) do
    defaults = %{
      file_path: "/media/test/#{Ecto.UUID.generate()}.mkv",
      watch_directory: "/media/test",
      parsed_title: "Test File",
      confidence: 0.5,
      tmdb_id: 12_345,
      tmdb_type: "movie",
      match_title: "Test Match"
    }

    Review.create_pending_file!(Map.merge(defaults, attrs))
  end

  def create_watch_progress(attrs) do
    defaults = %{position_seconds: 0.0, duration_seconds: 0.0}
    merged = Map.merge(defaults, Map.new(attrs))

    cond_result =
      cond do
        merged[:movie_id] -> Library.find_or_create_watch_progress_for_movie(merged)
        merged[:episode_id] -> Library.find_or_create_watch_progress_for_episode(merged)
        merged[:video_object_id] -> Library.find_or_create_watch_progress_for_video_object(merged)
      end

    # Preload `:playable_item` so tests can read the container_id back
    # without an extra DB round-trip (Library Schema v2 Phase 2 Task C
    # removed the direct `movie_id` / `episode_id` / `video_object_id`
    # columns; the container link lives on the PlayableItem).
    then(cond_result, fn {:ok, record} ->
      MediaCentarr.Repo.preload(record, :playable_item)
    end)
  end

  def create_extra_progress(attrs) do
    defaults = %{position_seconds: 0.0, duration_seconds: 0.0}
    Library.find_or_create_extra_progress!(Map.merge(defaults, attrs))
  end

  # ---------------------------------------------------------------------------
  # Release Tracking
  # ---------------------------------------------------------------------------

  alias MediaCentarr.ReleaseTracking

  def build_tracking_item(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      tmdb_id: :rand.uniform(999_999),
      media_type: :tv_series,
      name: "Test Tracked Series",
      status: :watching,
      source: :library,
      library_container_type: nil,
      library_container_id: nil,
      last_refreshed_at: nil,
      poster_path: nil,
      last_library_season: 0,
      last_library_episode: 0,
      releases: [],
      events: []
    }

    struct(ReleaseTracking.Item, Map.merge(defaults, overrides))
  end

  def build_tracking_release(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      air_date: Date.add(Date.utc_today(), 30),
      title: "Episode 1",
      season_number: 1,
      episode_number: 1,
      released: false,
      item_id: nil
    }

    struct(ReleaseTracking.Release, Map.merge(defaults, overrides))
  end

  def build_tracking_event(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      event_type: :began_tracking,
      description: "Began tracking Test Series",
      item_name: "Test Series",
      metadata: %{},
      item_id: nil
    }

    struct(ReleaseTracking.Event, Map.merge(defaults, overrides))
  end

  def create_tracking_item(attrs \\ %{}) do
    defaults = %{
      tmdb_id: :rand.uniform(999_999),
      media_type: :tv_series,
      name: "Test Tracked Series"
    }

    ReleaseTracking.track_item!(Map.merge(defaults, attrs))
  end

  def create_tracking_release(attrs) do
    ReleaseTracking.create_release!(attrs)
  end

  # ---------------------------------------------------------------------------
  # WatchHistory
  # ---------------------------------------------------------------------------

  def build_watch_event(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      entity_type: :movie,
      movie_id: nil,
      episode_id: nil,
      video_object_id: nil,
      title: "Test Movie",
      duration_seconds: 7200.0,
      completed_at: DateTime.utc_now(:second)
    }

    struct(MediaCentarr.WatchHistory.Event, Map.merge(defaults, overrides))
  end

  def create_watch_event(attrs \\ %{}) do
    defaults = %{
      entity_type: :movie,
      title: "Test Movie",
      duration_seconds: 7200.0,
      completed_at: DateTime.utc_now(:second)
    }

    {:ok, event} = MediaCentarr.WatchHistory.create_event(Map.merge(defaults, attrs))

    event
  end

  def create_pursuit(attrs \\ %{}) do
    defaults = %{
      tmdb_id: "12345",
      tmdb_type: "movie",
      title: "Sample Movie",
      origin: "auto"
    }

    merged = Map.merge(defaults, attrs)

    cast_keys = [
      :tmdb_id,
      :tmdb_type,
      :title,
      :year,
      :season_number,
      :episode_number,
      :origin,
      :criteria
    ]

    cast_attrs = Map.take(merged, cast_keys)
    internal_attrs = Map.drop(merged, cast_keys)

    {:ok, pursuit} =
      MediaCentarr.Repo.insert(MediaCentarr.Acquisition.Pursuits.Pursuit.create_changeset(cast_attrs))

    if internal_attrs == %{} do
      pursuit
    else
      {:ok, updated} =
        pursuit
        |> Ecto.Changeset.change(internal_attrs)
        |> MediaCentarr.Repo.update()

      updated
    end
  end

  def create_pursuit_event(pursuit, kind, attrs \\ %{}) do
    defaults = %{
      pursuit_id: pursuit.id,
      denormalized_pursuit_title: pursuit.title,
      kind: kind,
      payload: %{},
      occurred_at: DateTime.utc_now(:second)
    }

    {:ok, event} =
      MediaCentarr.Repo.insert(
        MediaCentarr.Acquisition.Pursuits.Event.create_changeset(Map.merge(defaults, attrs))
      )

    event
  end

  @doc """
  Inserts a Pursuit + a current Target in `seeking` and returns `{pursuit, target}`.

  Replaces the legacy `create_grab/1` factory after the Pursuit/Target
  refactor — the recipe lives on the pursuit, target carries per-attempt
  facts. Tests that only want a Target can `{_, target} = create_pursuit_with_target(...)`.

  Pursuit-level overrides (recipe_type, tmdb_id, tmdb_type, season_number,
  episode_number, year, title, origin, manual_query, state) and
  target-level overrides (status, release_title, attempt_count, etc.)
  may both be supplied via `attrs` — keys are routed by their place
  on the schema.
  """
  def create_pursuit_with_target(attrs \\ %{}) do
    pursuit_keys = [
      :recipe_type,
      :tmdb_id,
      :tmdb_type,
      :title,
      :year,
      :season_number,
      :episode_number,
      :origin,
      :manual_query,
      :criteria,
      :state,
      :attempt_count,
      :tried_release_guids
    ]

    target_keys = [
      :status,
      :release_title,
      :quality,
      :attempt_count,
      :acquired_at,
      :last_attempt_at,
      :last_attempt_outcome,
      :cancelled_at,
      :cancelled_reason,
      :prowlarr_guid
    ]

    defaults = %{
      recipe_type: "tmdb",
      tmdb_id: "12345",
      tmdb_type: "movie",
      title: "Sample Movie",
      origin: "auto"
    }

    merged = Map.merge(defaults, attrs)
    pursuit_attrs = Map.take(merged, pursuit_keys)
    target_attrs = Map.take(merged, target_keys)

    now = DateTime.utc_now(:second)

    {:ok, pursuit} =
      %MediaCentarr.Acquisition.Pursuits.Pursuit{}
      |> Ecto.Changeset.change(Map.put_new(pursuit_attrs, :state, "active"))
      |> Ecto.Changeset.change(inserted_at: now, updated_at: now)
      |> MediaCentarr.Repo.insert()

    target_base =
      target_attrs
      |> Map.put_new(:status, "seeking")
      |> Map.put(:pursuit_id, pursuit.id)
      |> Map.put(:title, pursuit.title)
      |> Map.put(:origin, pursuit.origin)
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    {:ok, target} =
      %MediaCentarr.Acquisition.Target{}
      |> Ecto.Changeset.change(target_base)
      |> MediaCentarr.Repo.insert()

    {:ok, pursuit} =
      pursuit
      |> Ecto.Changeset.change(current_target_id: target.id)
      |> MediaCentarr.Repo.update()

    {pursuit, target}
  end

  @doc "Convenience: just the target from `create_pursuit_with_target/1`."
  def create_target(attrs \\ %{}) do
    {_pursuit, target} = create_pursuit_with_target(attrs)
    target
  end

  # ---------------------------------------------------------------------------
  # Polymorphic owner translation (Library Schema v2 Phase 2 Tasks D, E, F)
  # ---------------------------------------------------------------------------

  # Test sites still use the legacy per-type FK keys (`movie_id:`,
  # `tv_series_id:`, `season_id:`, …) when building Image / Extra /
  # ExternalId rows. The schemas now carry a single `(owner_type,
  # owner_id)` discriminator pair. This translation lets existing tests
  # keep their natural call shape; new tests can write either form.
  #
  # If both legacy and modern keys are present, the modern keys win.

  @image_owner_keys [:movie_id, :episode_id, :tv_series_id, :movie_series_id, :video_object_id]
  @extra_owner_keys [:movie_id, :tv_series_id, :movie_series_id, :season_id]
  @external_id_owner_keys [:movie_id, :tv_series_id, :movie_series_id, :video_object_id]

  @owner_key_to_type %{
    movie_id: :movie,
    episode_id: :episode,
    tv_series_id: :tv_series,
    movie_series_id: :movie_series,
    video_object_id: :video_object,
    season_id: :season
  }

  defp translate_owner_keys(attrs, kind) do
    attrs = Map.new(attrs)
    keys = owner_keys_for(kind)

    case Enum.find(keys, fn key -> not is_nil(Map.get(attrs, key)) end) do
      nil ->
        attrs

      legacy_key ->
        owner_id = Map.get(attrs, legacy_key)
        owner_type = Map.fetch!(@owner_key_to_type, legacy_key)

        attrs
        |> Map.drop(keys)
        |> Map.put_new(:owner_type, owner_type)
        |> Map.put_new(:owner_id, owner_id)
    end
  end

  defp owner_keys_for(:image), do: @image_owner_keys
  defp owner_keys_for(:extra), do: @extra_owner_keys
  defp owner_keys_for(:external_id), do: @external_id_owner_keys
end
