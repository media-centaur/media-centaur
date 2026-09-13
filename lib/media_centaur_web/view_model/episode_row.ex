defmodule MediaCentaurWeb.ViewModel.EpisodeRow do
  @moduledoc """
  Tagged-struct ADT for the rows of a TV-series season, as consumed by
  `MediaCentaurWeb.Components.Detail.SeasonList`.

  "Episode list" names the data — `MediaCentaur.Library.Season`'s stored
  list of the episodes TMDB says a season has. These are the rows that
  list produces once it is joined against the files on disk, which is
  why they are rows and not list items.

  Three variants:

    * `Library` — a real `MediaCentaur.Library.Episode` we have a file
      for. Carries precomputed `state` and `is_resume_target` so the
      renderer doesn't have to recompute them per row.
    * `Missing` — an episode that has aired (or carries no air date)
      that the library has no file for. Actionable: clicking it
      downloads that episode.
    * `Upcoming` — an episode that has not aired yet. Rendered muted
      with a date pill, and not focusable — there is nothing to do
      with it.

  The distinction is the air date and nothing else. Until 2026-09-13 it
  was partly the *source*: a release-tracking row for an aired episode
  became `Upcoming{sub_status: :aired_not_in_library}`, so the same
  state rendered as an unclickable pill on a tracked series and as a
  clickable gap on an untracked one.

  These structs are populated by
  `MediaCentaurWeb.ViewModel.SeriesDetail.compose/2`. The component
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
            episode: MediaCentaur.Library.Episode.t(),
            season_number: non_neg_integer(),
            progress: MediaCentaur.Library.WatchProgress.t() | nil,
            state: state,
            is_resume_target: boolean()
          }
  end

  defmodule Missing do
    @moduledoc """
    An episode that has aired — or carries no air date — that the library
    holds no file for. Two sources produce it: an entry in the season's
    `episode_list`, and a release-tracking row for a tracked series. They
    are the same state, so they are the same row.

    `title` and `air_date` are whatever the producing source knew — a
    release row's title beats a list entry's name, and the row wears an
    "aired 3d ago" pill when it has a date.
    """

    @enforce_keys [:season_number, :episode_number]
    defstruct [:season_number, :episode_number, :title, :air_date]

    @type t :: %__MODULE__{
            season_number: non_neg_integer(),
            episode_number: non_neg_integer(),
            title: String.t() | nil,
            air_date: Date.t() | nil
          }
  end

  defmodule Upcoming do
    @moduledoc """
    An episode that has not aired yet: `air_date` is in the future, or nil
    for a release TMDB has scheduled without dating. Rendered muted with a
    date pill ("in 7d", "May 15", "TBA").

    Aired-but-absent is `Missing`, not a sub-status here.
    """

    @enforce_keys [:season_number, :episode_number]
    defstruct [:season_number, :episode_number, :title, :air_date]

    @type t :: %__MODULE__{
            season_number: non_neg_integer(),
            episode_number: non_neg_integer(),
            title: String.t() | nil,
            air_date: Date.t() | nil
          }
  end

  @type t :: Library.t() | Missing.t() | Upcoming.t()
end
