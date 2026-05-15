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
      movie_id: nil,
      episode_id: nil
    }

    struct(Image, Map.merge(defaults, overrides))
  end

  def build_external_id(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      source: "tmdb",
      external_id: "12345"
    }

    struct(ExternalId, Map.merge(defaults, overrides))
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
      season_id: nil
    }

    struct(Extra, Map.merge(defaults, overrides))
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
    defaults = %{
      episode_id: nil,
      movie_id: nil,
      video_object_id: nil,
      position_seconds: 0.0,
      duration_seconds: 0.0,
      completed: false,
      last_watched_at: DateTime.utc_now()
    }

    Map.merge(defaults, overrides)
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

    merged = Map.merge(defaults, Map.drop(attrs, [:type, :tmdb_id, :imdb_id]))

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

    record
  end

  def create_image(attrs) do
    Library.create_image!(attrs)
  end

  def create_external_id(attrs) do
    Library.create_external_id!(attrs)
  end

  def create_season(attrs) do
    Library.create_season!(attrs)
  end

  def create_episode(attrs) do
    Library.create_episode!(attrs)
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
  defp create_with_external_ids(type, defaults, attrs, creator) do
    tmdb_id = attrs[:tmdb_id]
    imdb_id = attrs[:imdb_id]
    clean_attrs = defaults |> Map.merge(attrs) |> Map.drop([:tmdb_id, :imdb_id])

    record = creator.(clean_attrs)
    tmdb_source = if type == :movie_series, do: :tmdb_collection, else: :tmdb
    _ = Library.ExternalIds.put(tmdb_source, record, tmdb_id)
    _ = Library.ExternalIds.put(:imdb, record, imdb_id)
    record
  end

  def create_standalone_movie(attrs \\ %{}) do
    defaults = %{name: "Test Standalone Movie", position: 0}
    tmdb_id = attrs[:tmdb_id]
    imdb_id = attrs[:imdb_id]
    movie_attrs = defaults |> Map.merge(attrs) |> Map.drop([:tmdb_id, :imdb_id])

    record = Library.create_movie!(movie_attrs)
    _ = Library.ExternalIds.put(:tmdb, record, tmdb_id)
    _ = Library.ExternalIds.put(:imdb, record, imdb_id)
    record
  end

  def create_extra(attrs) do
    Library.create_extra!(attrs)
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

  def create_linked_file(attrs \\ %{}) do
    defaults = %{
      file_path: "/media/test/#{Ecto.UUID.generate()}.mkv",
      watch_dir: "/media/test"
    }

    Library.link_file!(Map.merge(defaults, attrs))
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
    merged = Map.merge(defaults, attrs)

    cond_result =
      cond do
        merged[:movie_id] -> Library.find_or_create_watch_progress_for_movie(merged)
        merged[:episode_id] -> Library.find_or_create_watch_progress_for_episode(merged)
        merged[:video_object_id] -> Library.find_or_create_watch_progress_for_video_object(merged)
      end

    then(cond_result, fn {:ok, record} -> record end)
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
      library_entity_id: nil,
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
end
