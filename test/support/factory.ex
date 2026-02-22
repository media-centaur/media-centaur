defmodule MediaManager.TestFactory do
  @moduledoc """
  Shared test data builders.

  - `build_*` functions return plain structs with sensible defaults (no DB).
    Use for pure-function tests (Serializer, Mapper, ProgressSummary, etc.).
  - `create_*` functions persist via Ash actions and return loaded records.
    Use for resource tests and channel tests.
  """

  alias MediaManager.Library.{
    Entity,
    Extra,
    Image,
    Identifier,
    Movie,
    Season,
    Episode,
    WatchedFile
  }

  # ---------------------------------------------------------------------------
  # build_* — plain structs, no database
  # ---------------------------------------------------------------------------

  def build_entity(overrides \\ %{}) do
    defaults = %{
      id: Ash.UUID.generate(),
      type: :movie,
      name: "Test Movie",
      description: nil,
      date_published: nil,
      genres: nil,
      content_url: nil,
      url: nil,
      duration: nil,
      director: nil,
      content_rating: nil,
      number_of_seasons: nil,
      aggregate_rating_value: nil,
      images: [],
      identifiers: [],
      movies: [],
      extras: [],
      seasons: [],
      watched_files: [],
      watch_progress: []
    }

    struct(Entity, Map.merge(defaults, overrides))
  end

  def build_image(overrides \\ %{}) do
    defaults = %{
      id: Ash.UUID.generate(),
      role: "poster",
      url: "https://image.tmdb.org/t/p/original/test.jpg",
      content_url: nil,
      extension: "jpg",
      entity_id: nil,
      movie_id: nil,
      episode_id: nil
    }

    struct(Image, Map.merge(defaults, overrides))
  end

  def build_identifier(overrides \\ %{}) do
    defaults = %{
      id: Ash.UUID.generate(),
      property_id: "tmdb",
      value: "12345",
      entity_id: nil
    }

    struct(Identifier, Map.merge(defaults, overrides))
  end

  def build_movie(overrides \\ %{}) do
    defaults = %{
      id: Ash.UUID.generate(),
      name: "Child Movie",
      description: nil,
      date_published: nil,
      duration: nil,
      director: nil,
      content_rating: nil,
      content_url: nil,
      url: nil,
      aggregate_rating_value: nil,
      tmdb_id: nil,
      position: 0,
      entity_id: nil,
      images: []
    }

    struct(Movie, Map.merge(defaults, overrides))
  end

  def build_extra(overrides \\ %{}) do
    defaults = %{
      id: Ash.UUID.generate(),
      name: "Behind the Scenes",
      content_url: "/path/to/extra.mkv",
      position: 0,
      entity_id: nil,
      season_id: nil
    }

    struct(Extra, Map.merge(defaults, overrides))
  end

  def build_season(overrides \\ %{}) do
    defaults = %{
      id: Ash.UUID.generate(),
      season_number: 1,
      number_of_episodes: 0,
      name: "Season 1",
      entity_id: nil,
      episodes: [],
      extras: []
    }

    struct(Season, Map.merge(defaults, overrides))
  end

  def build_episode(overrides \\ %{}) do
    defaults = %{
      id: Ash.UUID.generate(),
      episode_number: 1,
      name: "Pilot",
      description: nil,
      duration: nil,
      content_url: nil,
      season_id: nil,
      images: []
    }

    struct(Episode, Map.merge(defaults, overrides))
  end

  def build_progress(overrides \\ %{}) do
    defaults = %{
      season_number: nil,
      episode_number: nil,
      position_seconds: 0.0,
      duration_seconds: 0.0,
      completed: false,
      last_watched_at: DateTime.utc_now()
    }

    Map.merge(defaults, overrides)
  end

  # ---------------------------------------------------------------------------
  # create_* — persisted via Ash, returns loaded records
  # ---------------------------------------------------------------------------

  def create_entity(attrs \\ %{}) do
    defaults = %{type: :movie, name: "Test Movie"}

    Entity
    |> Ash.Changeset.for_create(:create_from_tmdb, Map.merge(defaults, attrs))
    |> Ash.create!()
  end

  def create_image(attrs) do
    Image
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  def create_identifier(attrs) do
    Identifier
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  def create_season(attrs) do
    Season
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  def create_episode(attrs) do
    Episode
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  def create_movie(attrs) do
    Movie
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  def create_extra(attrs) do
    Extra
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  def create_entity_with_associations(attrs \\ %{}) do
    entity = create_entity(attrs)

    create_image(%{
      entity_id: entity.id,
      role: "poster",
      url: "https://image.tmdb.org/t/p/original/poster.jpg",
      extension: "jpg"
    })

    create_identifier(%{
      entity_id: entity.id,
      property_id: "tmdb",
      value: attrs[:tmdb_id] || "99999"
    })

    # Reload with associations
    Ash.get!(Entity, entity.id, action: :with_associations)
  end

  def create_watched_file(attrs \\ %{}) do
    defaults = %{file_path: "/media/test/#{Ash.UUID.generate()}.mkv"}

    WatchedFile
    |> Ash.Changeset.for_create(:detect, Map.merge(defaults, attrs))
    |> Ash.create!()
  end

  def create_pending_review_file(attrs \\ %{}) do
    detect_attrs = Map.take(attrs, [:file_path])
    file = create_watched_file(detect_attrs)

    update_attrs =
      %{state: :pending_review}
      |> maybe_put(attrs, :tmdb_id)
      |> maybe_put(attrs, :confidence_score)
      |> maybe_put(attrs, :match_title)
      |> maybe_put(attrs, :match_year)
      |> maybe_put(attrs, :match_poster_path)

    file
    |> Ash.Changeset.for_update(:update_state, update_attrs)
    |> Ash.update!()
  end

  defp maybe_put(map, source, key) do
    if Map.has_key?(source, key), do: Map.put(map, key, source[key]), else: map
  end

  def create_watch_progress(attrs) do
    defaults = %{position_seconds: 0.0, duration_seconds: 0.0}

    MediaManager.Library.WatchProgress
    |> Ash.Changeset.for_create(:upsert_progress, Map.merge(defaults, attrs))
    |> Ash.create!()
  end
end
