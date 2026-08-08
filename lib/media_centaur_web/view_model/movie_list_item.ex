defmodule MediaCentaurWeb.ViewModel.MovieListItem do
  @moduledoc """
  Tagged-struct ADT for items in a movie collection's content list, as
  consumed by the detail modal's collection renderer. The movie-side
  counterpart of `MediaCentaurWeb.ViewModel.EpisodeListItem`.

  Two variants:

    * `Library` — a member movie we have a file for. Carries precomputed
      `state` and `is_resume_target` so the renderer doesn't have to
      recompute them per row.
    * `Upcoming` — an announced collection part from
      `MediaCentaur.ReleaseTracking` that isn't in the library yet:
      unaired (future / absent `air_date`) or aired but not imported.
      Rendered as a muted row with an air-date pill.

  There is no `Missing` variant: the Library does not store
  known-but-absent collection parts (member movies exist only once a
  file has been imported), so there is no data to gap-fill from. When a
  collection-completeness feature lands, the gap rows join this ADT as a
  third variant.

  Populated by `MediaCentaurWeb.ViewModel.CollectionDetail.build/4`.
  The component pattern-matches on struct type — no tuple ADTs.
  """

  defmodule Library do
    @moduledoc """
    A member movie the user can watch (file present). Precomputed
    `state` (`:unwatched | :current | :watched`) and `is_resume_target`
    (boolean) save the renderer from computing them per row.

    `movie` is either a `MediaCentaur.Library.Movie` struct or the lean
    projection map from
    `MediaCentaur.Library.Views.DetailItem.movie_entry_to_map/1` — read
    optional display fields (`:description`, `:duration_seconds`,
    `:images`) via `Map.get`.
    """

    @enforce_keys [:movie, :state, :is_resume_target]
    defstruct [:movie, :progress, :state, :is_resume_target]

    @type state :: :unwatched | :current | :watched
    @type t :: %__MODULE__{
            movie: map() | struct(),
            progress: MediaCentaur.Library.WatchProgress.t() | nil,
            state: state,
            is_resume_target: boolean()
          }
  end

  defmodule Upcoming do
    @moduledoc """
    An announced collection part. `sub_status` distinguishes:

      * `:unaired` — `air_date` is in the future (or absent).
      * `:aired_not_in_library` — `air_date` has passed but no file has
        been imported.

    One row per part: `MediaCentaur.ViewModel.CollectionDetail.build/4`
    dedupes multiple release rows for the same `part_tmdb_id`.
    """

    @enforce_keys [:part_tmdb_id, :sub_status]
    defstruct [:part_tmdb_id, :title, :air_date, :sub_status]

    @type sub_status :: :unaired | :aired_not_in_library
    @type t :: %__MODULE__{
            part_tmdb_id: integer(),
            title: String.t() | nil,
            air_date: Date.t() | nil,
            sub_status: sub_status
          }
  end

  @type t :: Library.t() | Upcoming.t()
end
