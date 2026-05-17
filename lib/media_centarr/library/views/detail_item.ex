defmodule MediaCentarr.Library.Views.DetailItem do
  @moduledoc """
  View-model for a single playable leaf (one `Library.PlayableItem`) plus
  the container metadata the detail panel renders. The public read
  contract of `MediaCentarr.Library.Views.detail/1` and
  `MediaCentarr.Library.Views.detail_by_container/2`.

  Per ADR-041, this struct decouples render shape from storage shape —
  UI consumers depend only on the field set declared here, not on the
  source-of-truth Ecto schemas.

  ## Composition with other view-models

  This projection holds Library-context-owned **static** data only.
  Two slices are deliberately overlaid by consumers at read time
  rather than embedded here:

    * **Watch progress** — embedding it would invalidate the
      projection on every playback position-tick.
      `Library.Progress.get/1` (Pillar-2 GenServer, ETS-backed,
      microsecond reads) is the canonical hot read; consumers
      overlay it onto `DetailItem.Episode` / `DetailItem.MovieEntry`
      at render time (same pattern as `BrowseItem` in Phase 3.1).
    * **Cross-context overlays** — `ReleaseTracking` releases,
      `Playback.MpvSession` now-playing, and `tracking_status` are
      composed at the LiveView layer, not in the projection.

  ## Field set

    * `:playable_item_id`           — UUID of the underlying `PlayableItem` (table key).
    * `:container_type`             — `:movie | :episode | :video_object` (leaf-level type).
    * `:container_id`               — UUID of the leaf container (Movie / Episode / VideoObject).
    * `:name`                       — leaf name (episode name) OR container name for solo containers.
    * `:position`                   — 1-based position of the PlayableItem within its container.
    * `:duration_seconds`           — leaf playback duration.
    * `:date_published`             — leaf-level publish date (falls back to container).
    * `:description`                — leaf-level description (falls back to container).
    * `:parent_container_type`      — for Episodes, `:tv_series`; nil otherwise.
    * `:parent_container_id`        — for Episodes, the TVSeries UUID; nil otherwise.
    * `:parent_container_name`      — for Episodes, the TVSeries name; nil otherwise.
    * `:container_name`             — top-level entity display name (TVSeries name for an
                                       episode, Movie name for a movie, etc.).
    * `:container_description`      — top-level entity description.
    * `:container_year`             — release year derived from container.date_published.
    * `:container_url`              — TMDB URL on the container.
    * `:container_tagline`          — marketing tagline (Movie / TVSeries).
    * `:container_genres`           — list of genre strings.
    * `:container_studio`           — production studio (Movie).
    * `:container_country_code`     — ISO 3166 country code.
    * `:container_original_language` — ISO 639 language code.
    * `:container_network`          — broadcast network (TVSeries).
    * `:container_status`           — production status atom.
    * `:container_duration_seconds` — runtime in seconds (Movie / Episode).
    * `:container_content_rating`   — MPAA/TV rating (Movie).
    * `:container_aggregate_rating` — float rating (Movie / TVSeries).
    * `:container_vote_count`       — TMDB vote count.
    * `:container_number_of_seasons` — TVSeries season count.
    * `:container_director`         — director name (Movie only).
    * `:cast`                       — `[%Library.Person{}]` embedded cast list.
    * `:crew`                       — `[%Library.Person{}]` embedded crew list.
    * `:extras`                     — `[%Library.Extra{}]` bonus features.
    * `:external_ids`               — `[%Library.ExternalId{}]` ID rows (TMDB, IMDB, etc.).
    * `:imdb_id`                    — convenience: IMDB id pulled from external_ids.
    * `:tmdb_id`                    — convenience: TMDB id pulled from external_ids.
    * `:present?`                   — `true` when at least one backing WatchedFile exists for
                                       the PlayableItem. Presence is structural after Phase 3
                                       (`WatchedFile.file_presence_id` FK with cascade-delete
                                       from `Library.FilePresence`).
    * `:images`                     — `[%Library.Image{}]` for hero / poster / logo render.
    * `:seasons`                    — `[%DetailItem.Season{}]` for TV-series containers
                                       (nil for movie / movie_series / video_object).
    * `:movies`                     — `[%DetailItem.MovieEntry{}]` for MovieSeries containers
                                       (nil for movie / tv_series / video_object).
    * `:watched_files`              — `[%DetailItem.WatchedFile{}]` — backing files on disk for
                                       this leaf's PlayableItem. Drives the modal's
                                       delete-file UX.
    * `:subtitle_tracks`            — `[%DetailItem.SubtitleTrack{}]` — detected subtitle tracks
                                       (embedded streams + sidecar files) for this leaf.
  """

  @enforce_keys [:playable_item_id, :container_type, :container_id, :name]
  defstruct [
    :playable_item_id,
    :container_type,
    :container_id,
    :name,
    :position,
    :duration_seconds,
    :date_published,
    :description,
    :parent_container_type,
    :parent_container_id,
    :parent_container_name,
    :container_name,
    :container_description,
    :container_year,
    :container_url,
    :container_tagline,
    :container_genres,
    :container_studio,
    :container_country_code,
    :container_original_language,
    :container_network,
    :container_status,
    :container_duration_seconds,
    :container_content_rating,
    :container_aggregate_rating,
    :container_vote_count,
    :container_number_of_seasons,
    :container_director,
    :cast,
    :crew,
    :extras,
    :external_ids,
    :imdb_id,
    :tmdb_id,
    :present?,
    :images,
    :seasons,
    :movies,
    :watched_files,
    :subtitle_tracks
  ]

  @type container_type :: :movie | :episode | :video_object

  @type t :: %__MODULE__{
          playable_item_id: Ecto.UUID.t(),
          container_type: container_type(),
          container_id: Ecto.UUID.t(),
          name: String.t(),
          position: integer() | nil,
          duration_seconds: integer() | nil,
          date_published: Date.t() | nil,
          description: String.t() | nil,
          parent_container_type: :tv_series | nil,
          parent_container_id: Ecto.UUID.t() | nil,
          parent_container_name: String.t() | nil,
          container_name: String.t() | nil,
          container_description: String.t() | nil,
          container_year: integer() | nil,
          container_url: String.t() | nil,
          container_tagline: String.t() | nil,
          container_genres: [String.t()] | nil,
          container_studio: String.t() | nil,
          container_country_code: String.t() | nil,
          container_original_language: String.t() | nil,
          container_network: String.t() | nil,
          container_status: atom() | nil,
          container_duration_seconds: integer() | nil,
          container_content_rating: String.t() | nil,
          container_aggregate_rating: float() | nil,
          container_vote_count: integer() | nil,
          container_number_of_seasons: integer() | nil,
          container_director: String.t() | nil,
          cast: [struct()] | nil,
          crew: [struct()] | nil,
          extras: [struct()] | nil,
          external_ids: [struct()] | nil,
          imdb_id: String.t() | nil,
          tmdb_id: String.t() | nil,
          present?: boolean() | nil,
          images: [struct()] | nil,
          seasons: [__MODULE__.Season.t()] | nil,
          movies: [__MODULE__.MovieEntry.t()] | nil,
          watched_files: [__MODULE__.WatchedFile.t()] | nil,
          subtitle_tracks: [__MODULE__.SubtitleTrack.t()] | nil
        }

  defmodule Season do
    @moduledoc """
    A TV-series season bucket inside `DetailItem.seasons`. Carries
    static season metadata + the `Episode` list. Per-episode watch
    progress is overlaid at the consumer (`Library.Progress.get/1`).

    `:number_of_episodes` mirrors the Season schema field — used by
    `SeriesDetail.build/4` to gap-fill `EpisodeListItem.Missing` rows
    when TMDB reports more episodes than the library has imported.
    """

    @enforce_keys [:season_number, :episodes]
    defstruct [:season_number, :name, :episodes, :number_of_episodes, extras: []]

    @type t :: %__MODULE__{
            season_number: non_neg_integer(),
            name: String.t() | nil,
            episodes: [MediaCentarr.Library.Views.DetailItem.Episode.t()],
            number_of_episodes: non_neg_integer() | nil,
            extras: [struct()]
          }
  end

  defmodule Episode do
    @moduledoc """
    A single TV episode inside `DetailItem.Season.episodes`. Static
    episode metadata only. `WatchProgress` is overlaid at the consumer.

    `:content_url` is the file path of the first linked `WatchedFile`
    under the episode's `PlayableItem` — needed by `ResumeTarget` and
    the episode-list renderer to wire the play button.

    `:images` carries per-episode `Library.Image` rows (typically a
    `"thumb"` for the episode-row render). Defaults to `[]` so consumers
    that dot-access `:images` cannot `KeyError` on episodes without
    artwork.
    """

    @enforce_keys [:episode_id, :playable_item_id, :season_number, :episode_number, :name]
    defstruct [
      :episode_id,
      :playable_item_id,
      :season_number,
      :episode_number,
      :name,
      :description,
      :date_published,
      :duration_seconds,
      :present?,
      :content_url,
      images: []
    ]

    @type t :: %__MODULE__{
            episode_id: Ecto.UUID.t(),
            playable_item_id: Ecto.UUID.t(),
            season_number: non_neg_integer(),
            episode_number: non_neg_integer(),
            name: String.t(),
            description: String.t() | nil,
            date_published: Date.t() | nil,
            duration_seconds: integer() | nil,
            present?: boolean() | nil,
            content_url: String.t() | nil,
            images: [struct()]
          }
  end

  defmodule MovieEntry do
    @moduledoc """
    A single constituent movie inside `DetailItem.movies` for a
    MovieSeries container. Static movie metadata; `WatchProgress` is
    overlaid at the consumer.
    """

    @enforce_keys [:movie_id, :playable_item_id, :name]
    defstruct [
      :movie_id,
      :playable_item_id,
      :name,
      :date_published,
      :collection_position,
      :content_url,
      :present?
    ]

    @type t :: %__MODULE__{
            movie_id: Ecto.UUID.t(),
            playable_item_id: Ecto.UUID.t(),
            name: String.t(),
            date_published: Date.t() | nil,
            collection_position: integer() | nil,
            content_url: String.t() | nil,
            present?: boolean() | nil
          }
  end

  defmodule WatchedFile do
    @moduledoc """
    A backing file on disk for a leaf's `PlayableItem`. The modal's
    delete-file UX renders one row per `WatchedFile`.
    """

    @enforce_keys [:path, :watch_dir]
    defstruct [:path, :watch_dir]

    @type t :: %__MODULE__{
            path: String.t(),
            watch_dir: String.t()
          }
  end

  defmodule SubtitleTrack do
    @moduledoc """
    A detected subtitle track. `:embedded` tracks live inside the
    video container (`source` is the ffmpeg stream index); `:sidecar`
    tracks are external `.srt` / `.ass` files (`source` is the
    sidecar path).
    """

    @enforce_keys [:kind, :language]
    defstruct [:kind, :language, :source]

    @type kind :: :embedded | :sidecar
    @type t :: %__MODULE__{
            kind: kind(),
            language: String.t(),
            source: String.t() | nil
          }
  end

  @doc """
  Adapts a `DetailItem` into the polymorphic entity-map shape today's
  consumers
  (`MediaCentarrWeb.ViewModel.SeriesDetail.build/4`,
  `MediaCentarrWeb.Components.DetailPanel`,
  `MediaCentarr.Playback.ResumeTarget.compute/2`,
  `MediaCentarrWeb.Live.EntityModal.find_tmdb_id/1`,
  `MediaCentarrWeb.Live.EntityModal.resolve_progress_fk/4`) consume.

  Dispatches on `(parent_container_type, container_type)` to produce
  the right shape for each modal kind:

    * `parent_container_type: :tv_series` → TV-series entity-map (Task C.2).
    * `parent_container_type: :movie_series, container_type: :movie`
      → MovieSeries entity-map (Task D). The DetailItem is a canonical
      child Movie carrying the full `:movies` tree.
    * `container_type: :movie` → standalone (or hoisted-collection) Movie
      entity-map (Task D).
    * `container_type: :video_object` → VideoObject entity-map (Task D).

  Pure: no DB, no side effects. Library Schema v2 Phase 3.2 introduces
  this as a temporary compatibility shim — Task E retires it when the
  DetailPanel consumer tree migrates to typed `DetailItem` attrs.
  """
  @spec to_entity_map(t()) :: map()
  def to_entity_map(%__MODULE__{parent_container_type: :tv_series} = item) do
    %{
      id: item.parent_container_id,
      type: :tv_series,
      name: item.container_name,
      description: item.container_description,
      date_published: nil,
      content_url: nil,
      url: item.container_url,
      tagline: item.container_tagline,
      genres: item.container_genres,
      studio: item.container_studio,
      country_code: item.container_country_code,
      original_language: item.container_original_language,
      network: item.container_network,
      status: item.container_status,
      duration_seconds: item.container_duration_seconds,
      content_rating: item.container_content_rating,
      aggregate_rating_value: item.container_aggregate_rating,
      vote_count: item.container_vote_count,
      number_of_seasons: item.container_number_of_seasons,
      director: nil,
      cast: item.cast || [],
      crew: item.crew || [],
      extras: item.extras || [],
      external_ids: item.external_ids || [],
      imdb_id: item.imdb_id,
      tmdb_id: item.tmdb_id,
      images: item.images || [],
      seasons: Enum.map(item.seasons || [], &season_to_map/1),
      movies: [],
      watched_files: [],
      subtitle_tracks: [],
      extra_progress: []
    }
  end

  def to_entity_map(%__MODULE__{parent_container_type: :movie_series, container_type: :movie} = item) do
    %{
      id: item.parent_container_id,
      type: :movie_series,
      name: item.container_name,
      description: item.container_description,
      date_published: nil,
      content_url: nil,
      url: item.container_url,
      tagline: item.container_tagline,
      genres: item.container_genres,
      studio: item.container_studio,
      country_code: item.container_country_code,
      original_language: item.container_original_language,
      network: nil,
      status: item.container_status,
      duration_seconds: nil,
      content_rating: item.container_content_rating,
      aggregate_rating_value: item.container_aggregate_rating,
      vote_count: item.container_vote_count,
      number_of_seasons: nil,
      director: nil,
      cast: item.cast || [],
      crew: item.crew || [],
      extras: item.extras || [],
      external_ids: item.external_ids || [],
      imdb_id: item.imdb_id,
      tmdb_id: item.tmdb_id,
      images: item.images || [],
      seasons: [],
      movies: Enum.map(item.movies || [], &movie_entry_to_map/1),
      watched_files: [],
      subtitle_tracks: [],
      extra_progress: []
    }
  end

  def to_entity_map(%__MODULE__{container_type: :movie} = item) do
    %{
      id: item.container_id,
      type: :movie,
      name: item.container_name,
      description: item.container_description,
      date_published: item.date_published,
      content_url: first_watched_file_path(item),
      url: item.container_url,
      tagline: item.container_tagline,
      genres: item.container_genres,
      studio: item.container_studio,
      country_code: item.container_country_code,
      original_language: item.container_original_language,
      network: nil,
      status: item.container_status,
      duration_seconds: item.container_duration_seconds,
      content_rating: item.container_content_rating,
      aggregate_rating_value: item.container_aggregate_rating,
      vote_count: item.container_vote_count,
      number_of_seasons: nil,
      director: item.container_director,
      cast: item.cast || [],
      crew: item.crew || [],
      extras: item.extras || [],
      external_ids: item.external_ids || [],
      imdb_id: item.imdb_id,
      tmdb_id: item.tmdb_id,
      images: item.images || [],
      seasons: [],
      movies: [],
      watched_files: [],
      subtitle_tracks: item.subtitle_tracks || [],
      extra_progress: []
    }
  end

  def to_entity_map(%__MODULE__{container_type: :video_object} = item) do
    %{
      id: item.container_id,
      type: :video_object,
      name: item.container_name,
      description: item.container_description,
      date_published: item.date_published,
      content_url: first_watched_file_path(item),
      url: item.container_url,
      tagline: nil,
      genres: item.container_genres,
      studio: nil,
      country_code: item.container_country_code,
      original_language: item.container_original_language,
      network: nil,
      status: nil,
      duration_seconds: item.container_duration_seconds,
      content_rating: nil,
      aggregate_rating_value: item.container_aggregate_rating,
      vote_count: item.container_vote_count,
      number_of_seasons: nil,
      director: nil,
      cast: item.cast || [],
      crew: item.crew || [],
      extras: item.extras || [],
      external_ids: item.external_ids || [],
      imdb_id: item.imdb_id,
      tmdb_id: item.tmdb_id,
      images: item.images || [],
      seasons: [],
      movies: [],
      watched_files: [],
      subtitle_tracks: item.subtitle_tracks || [],
      extra_progress: []
    }
  end

  defp season_to_map(%__MODULE__.Season{} = season) do
    %{
      season_number: season.season_number,
      name: season.name,
      number_of_episodes: season.number_of_episodes,
      extras: season.extras || [],
      episodes: Enum.map(season.episodes || [], &episode_to_map/1)
    }
  end

  defp episode_to_map(%__MODULE__.Episode{} = episode) do
    %{
      id: episode.episode_id,
      episode_number: episode.episode_number,
      name: episode.name,
      description: episode.description,
      date_published: episode.date_published,
      duration_seconds: episode.duration_seconds,
      content_url: episode.content_url,
      images: episode.images || []
    }
  end

  defp first_watched_file_path(%__MODULE__{watched_files: [%__MODULE__.WatchedFile{path: path} | _]}),
    do: path

  defp first_watched_file_path(_), do: nil

  defp movie_entry_to_map(%__MODULE__.MovieEntry{} = entry) do
    %{
      id: entry.movie_id,
      name: entry.name,
      date_published: entry.date_published,
      collection_position: entry.collection_position,
      content_url: entry.content_url,
      present?: entry.present?
    }
  end
end
