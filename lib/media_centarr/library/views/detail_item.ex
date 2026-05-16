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

  This projection holds Library-context-owned data only. Watch progress
  is composed at the consumer via `Library.WatchProgress` reads (or the
  Phase 3 Task D in-memory `Library.Progress` GenServer). Active playback
  session info is composed via `MediaCentarr.Playback`. The split keeps
  per-row rebuilds cheap — a position tick during playback should not
  invalidate the detail row's metadata cache.

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
    * `:cast`                       — `[%Library.Person{}]` embedded cast list.
    * `:crew`                       — `[%Library.Person{}]` embedded crew list.
    * `:extras`                     — `[%Library.Extra{}]` bonus features.
    * `:external_ids`               — `[%Library.ExternalId{}]` ID rows (TMDB, IMDB, etc.).
    * `:imdb_id`                    — convenience: IMDB id pulled from external_ids.
    * `:tmdb_id`                    — convenience: TMDB id pulled from external_ids.
    * `:present?`                   — `true` when at least one backing WatchedFile is in the
                                       `:present` state via `Watcher.KnownFile`.
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
    :cast,
    :crew,
    :extras,
    :external_ids,
    :imdb_id,
    :tmdb_id,
    :present?
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
          cast: [struct()] | nil,
          crew: [struct()] | nil,
          extras: [struct()] | nil,
          external_ids: [struct()] | nil,
          imdb_id: String.t() | nil,
          tmdb_id: String.t() | nil,
          present?: boolean() | nil
        }
end
