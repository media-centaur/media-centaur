defmodule MediaCentaur.Acquisition.Plans.Doors do
  @moduledoc """
  Every way a plan comes into being, named in one place.

  A **door** is a function that creates an acquisition plan. There are
  more of them than the phrase "the plan doors" suggests, and that is the
  point of this module: *release tracking* reads as a single door and is
  four separate code paths. When identity-by-id shipped, three were
  wired and the fourth was not, because the set of doors existed only in
  the author's head. The unattended movie door then built its plans from
  the title alone for five days, grabbing a different film that shared
  its ASCII-folded name once a day.

  Two guards keep that from recurring, and they do different jobs:

    * `Plans.create_plan/2` accepts a `TMDB.TitleIdentity` and nothing
      else, so a door **cannot be half-built** — the compiler says so.
    * `MC0037` refuses a plan-creating function missing from
      `registry/0`, so a door **cannot be unknown**.

  The first is about correctness, the second about discoverability. The
  bug needed both to be missed.

  This list is documentation the build enforces. It is not consulted at
  runtime, and adding an entry grants nothing — it only records that a
  door was added deliberately, by someone who saw the others.
  """

  @type door :: %{
          module: module(),
          function: atom(),
          opens: String.t(),
          identity_from: String.t()
        }

  @doc """
  Every plan door: where it lives, what opens it, and where the title's
  identity comes from when it does.

  `identity_from` is the interesting column. A door holding a TMDB
  payload reads identity straight off it; a door working from stored
  state reads it from there. The one door with neither — Discovery's
  one-click movie — fetches its own, inside the background task it
  already runs in.
  """
  @spec registry() :: [door()]
  def registry do
    [
      %{
        module: MediaCentaur.Acquisition.Plans,
        function: :create_series_plan,
        opens: "media search, for a series the person picked from the plan modal",
        identity_from: "the Targeting.Selection its TMDB fetch produced"
      },
      %{
        module: MediaCentaur.Acquisition.Plans,
        function: :create_movie_plan,
        opens: "media search, for a film the person confirmed",
        identity_from: "the Detail.TitlePreview the confirm step already holds"
      },
      %{
        module: MediaCentaur.Acquisition.Plans,
        function: :do_plan_title,
        opens: "Discovery's one-click download, for a film or a series",
        identity_from: "a TMDB detail it fetches itself — the only door holding no payload already"
      },
      %{
        module: MediaCentaurWeb.IncomingLive,
        function: :handle_event,
        opens: "the Create plan button in the plan modal, for a series or a film",
        identity_from:
          "nothing of its own — it hands the picker's selection or preview to the " <>
            "two doors above. Listed because a reader asking where plans come from " <>
            "wants to find the button, not only the function behind it."
      },
      %{
        module: MediaCentaur.Acquisition.DropPlanner,
        function: :plan_now,
        opens: "the person pressing Plan now on a tracked title (series or film)",
        identity_from: "the tracked title, via ReleaseTracking.Identity"
      },
      %{
        module: MediaCentaur.Acquisition.DropPlanner,
        function: :plan_tv_drop,
        opens: "the automatic sweep, for a series with due wants",
        identity_from: "the tracked title, via ReleaseTracking.Identity.for_item/1"
      },
      %{
        module: MediaCentaur.Acquisition.DropPlanner,
        function: :plan_movie_drop,
        opens: "the automatic sweep, for a film with a due want",
        identity_from:
          "the want, via ReleaseTracking.Identity.for_want/2 — the tracked film's own " <>
            "identity when the want is that film, the part's bare id when it is a " <>
            "collection part. This is the door that shipped without one."
      }
    ]
  end
end
