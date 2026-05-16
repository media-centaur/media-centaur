defmodule MediaCentarr.Library.Views.BrowseItem do
  @moduledoc """
  View-model for one row of the Library Browse projection (ADR-041,
  Library Schema v2 Phase 3 Task A).

  This is the public read contract of `MediaCentarr.Library.Views`'s
  `browse/1` function. Per ADR-041, the view-model struct decouples
  render shape from storage shape — UI consumers depend only on the
  field set declared here, not on the source-of-truth Ecto schemas.

  ## Field set

    * `:id`         — container UUID (Movie / TVSeries / MovieSeries / VideoObject)
    * `:kind`       — `:movie | :tv_series | :movie_series | :video_object`
    * `:name`       — human-readable display title
    * `:year`       — release year derived from `container.date_published.year`
    * `:poster_url` — local artwork URL (`/media-images/<content_url>`) or nil
    * `:present?`   — `true` when at least one backing file is currently
                      reachable. The projection already filters to
                      present-only entities at query time, so this
                      defaults to `true`; the flag stays in the shape
                      so the `:present_only` filter in `Views.browse/1`
                      stays meaningful when the underlying query
                      relaxes later.
    * `:rank`       — 0-indexed display rank, assigned by `refresh_cache/0`
                      after the source query runs.
  """

  @enforce_keys [:id, :kind, :name]
  defstruct [:id, :kind, :name, :year, :poster_url, :present?, :rank]

  @type kind :: :movie | :tv_series | :movie_series | :video_object

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          kind: kind(),
          name: String.t(),
          year: integer() | nil,
          poster_url: String.t() | nil,
          present?: boolean() | nil,
          rank: non_neg_integer() | nil
        }
end
