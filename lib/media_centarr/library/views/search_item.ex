defmodule MediaCentarr.Library.Views.SearchItem do
  @moduledoc """
  View-model for one hit of the Library Search projection (ADR-041,
  Library Schema v2 Phase 3 Task C).

  This is the public read contract of `MediaCentarr.Library.Views`'s
  `search/2` function. Per ADR-041, the view-model struct decouples
  render shape from storage shape — UI consumers depend only on the
  field set declared here, not on the source-of-truth Ecto schemas.

  ## Field set

    * `:playable_item_id`  — canonical leaf for `Play` semantics. For
                             entities with multiple PlayableItems
                             (multi-cut Movies, multi-episode TVSeries),
                             this is a representative leaf (the
                             position-1 PlayableItem of the canonical
                             child). For TVSeries / MovieSeries, the
                             canonical leaf points at the first
                             episode / first child movie.
    * `:container_type`    — `:movie | :tv_series | :movie_series | :video_object | :episode`
    * `:container_id`      — top-level entity UUID (the thing the user
                             navigates to in the library / detail modal)
    * `:name`              — human-readable display title used for matching
    * `:year`              — release year derived from
                             `container.date_published.year`
    * `:score`             — match score in `[0.0, 1.0]`; higher is better.
                             Filled in by `Library.Views.search/2` per
                             query; nil on the raw stored row.
    * `:present?`          — `true` when at least one backing file is
                             currently reachable; false otherwise.
                             Stored on the row so the `:present_only`
                             filter doesn't have to re-derive presence
                             on every search call.
  """

  @enforce_keys [:playable_item_id, :container_type, :container_id, :name]
  defstruct [:playable_item_id, :container_type, :container_id, :name, :year, :score, :present?]

  @type container_type :: :movie | :tv_series | :movie_series | :video_object | :episode

  @type t :: %__MODULE__{
          playable_item_id: Ecto.UUID.t(),
          container_type: container_type(),
          container_id: Ecto.UUID.t(),
          name: String.t(),
          year: integer() | nil,
          score: float() | nil,
          present?: boolean() | nil
        }
end
