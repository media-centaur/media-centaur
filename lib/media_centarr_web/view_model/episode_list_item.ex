defmodule MediaCentarrWeb.ViewModel.EpisodeListItem do
  @moduledoc """
  Tagged-struct ADT for items in a TV-series season's episode list, as
  consumed by `MediaCentarrWeb.Components.DetailPanel.season_section/1`.

  Three variants:

    * `Library` — a real `MediaCentarr.Library.Episode` we have a file
      for. Carries precomputed `state` and `is_resume_target` so the
      renderer doesn't have to recompute them per row.
    * `Missing` — a gap in the library episode list: TMDB says
      episode N exists for the season but no file has been imported
      yet. Rendered as a quiet placeholder.
    * `Upcoming` — a `MediaCentarr.ReleaseTracking.Release` for an
      episode that's either unaired (`released: false`) or aired but
      not yet in the library (`released: true, in_library: false`).
      Rendered as a muted row with an air-date pill.

  The `Missing | Upcoming` distinction matters: Missing means "we
  expect a file eventually, no schedule info". Upcoming means "TMDB
  has scheduled it; here's the date".

  These structs are populated by
  `MediaCentarrWeb.ViewModel.SeriesDetail.compose/2`. The component
  pattern-matches on struct type — no tuple ADTs.
  """

  defmodule Library do
    @moduledoc """
    A library episode the user can watch (file present). Precomputed
    `state` (`:unwatched | :current | :watched`) and `is_resume_target`
    (boolean) save the renderer from computing them per-frame.
    """

    @enforce_keys [:episode, :season_number, :state, :is_resume_target]
    defstruct [:episode, :season_number, :progress, :state, :is_resume_target]

    @type state :: :unwatched | :current | :watched
    @type t :: %__MODULE__{
            episode: MediaCentarr.Library.Episode.t(),
            season_number: non_neg_integer(),
            progress: MediaCentarr.Library.WatchProgress.t() | nil,
            state: state,
            is_resume_target: boolean()
          }
  end

  defmodule Missing do
    @moduledoc """
    A gap in the library episode list — `season.number_of_episodes`
    says episode N exists but no file has been imported. No release
    record either (otherwise it would be an `Upcoming`).
    """

    @enforce_keys [:season_number, :episode_number]
    defstruct [:season_number, :episode_number]

    @type t :: %__MODULE__{
            season_number: non_neg_integer(),
            episode_number: non_neg_integer()
          }
  end

  defmodule Upcoming do
    @moduledoc """
    An episode TMDB has scheduled. `sub_status` distinguishes:

      * `:unaired` — `air_date` is in the future (`released: false`).
        The pill copy is "in 7d" / "May 15".
      * `:aired_not_in_library` — `air_date` is in the past
        (`released: true`, `in_library: false`). The pill copy is
        "aired 3d ago".

    `air_date` may be nil for releases TMDB hasn't dated yet (rare).
    """

    @enforce_keys [:season_number, :episode_number, :sub_status]
    defstruct [:season_number, :episode_number, :title, :air_date, :sub_status]

    @type sub_status :: :unaired | :aired_not_in_library
    @type t :: %__MODULE__{
            season_number: non_neg_integer(),
            episode_number: non_neg_integer(),
            title: String.t() | nil,
            air_date: Date.t() | nil,
            sub_status: sub_status
          }
  end

  @type t :: Library.t() | Missing.t() | Upcoming.t()
end
