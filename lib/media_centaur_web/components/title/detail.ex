defmodule MediaCentaurWeb.Components.Title.Detail do
  @moduledoc """
  The title detail modal's view-model (UIDR-043): one TMDB title —
  owned or not — with every fact the app knows about it, built by
  `Logic.title_detail/2` from facts the host resolved by identity. It
  carries facts and nothing derived from them: which primary action the
  strip offers, whether the tracking card shows, whether a series'
  Download carries a scope are each computed where the section mounts
  (`Detail.Logic.primary_action/2`, `Detail.Logic.tracking_card?/1`).

  `library` is the library half (`Detail.Library`) when the library owns
  the title — the typed entry, the subject, the selected member, the
  files, availability — and nil when it does not; files are one more
  fact, not a different surface. The residue — a library entity with no
  TMDB identity (a video object, an unmatched container), addressed by
  entity id — is a detail with `ref` and `title` nil and the library
  half as its one fact. `acquisition_state` is the title's
  plan or pursuit in flight (`Acquisition.TitleStates`), and
  `release_mode_available` whether an indexer is ready to be asked for
  a release. `planning_mode` is the person's default planning mode
  (`Settings.Preferences.PlanningMode`), read on build.

  `tracking` is the tracked-title half (`TrackingDetail`): nil for a
  title that has never been tracked. `acquisition?`, `complete?` and
  `release_window` are what the tracking controls need: whether a grab
  can fire, whether the library already owns the film
  (`ReleaseTracking.complete?/2`), and where a movie stands in its
  release sequence — nil until the live preview lands, and for a
  series. The rows derive their rule from these at the mount
  (`Logic.release_ahead?/3`).

  `friend_activity` is the title's `Activities.friend_activity_for/1`
  rows — the hero's pennants (UIDR-037). `activity` is the one row the
  modal speaks for, read by identity from the `activity` param: a
  friend's, so that listing the title records where it came from and
  their words lead the body; an own one, opened from the You card, so
  that Delete <noun> can withdraw it. `intent_note` is the person's own
  watchlist note. The note line is derived from the two at the mount.

  `preview` is the live TMDB-backed `Detail.TitlePreview` the host
  fetches on open for an unowned title; nil until it lands, when TMDB is
  not configured, and for an owned title, whose entity is the richer
  source.
  """

  alias MediaCentaur.Activities
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.TMDB.ReleaseWindow
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail
  alias MediaCentaurWeb.Components.Title.Detail.Library

  @enforce_keys [:ref, :title]
  defstruct [
    :ref,
    :title,
    :poster_url,
    :backdrop_url,
    :logo_url,
    :library,
    :acquisition_state,
    :rung,
    :tracking,
    :release_window,
    :activity,
    :intent_note,
    :preview,
    release_mode_available: false,
    acquisition?: false,
    lower_quality_accepted?: false,
    complete?: false,
    planning_mode: :manually_select_release,
    friend_activity: []
  ]

  @type acquisition_state :: :planning | :downloading | :needs_review | nil

  @type t :: %__MODULE__{
          ref: {integer(), Title.media_type()} | nil,
          title: Title.t() | nil,
          poster_url: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil,
          library: Library.t() | nil,
          acquisition_state: acquisition_state(),
          release_mode_available: boolean(),
          rung: MediaCentaur.Discovery.TitleIntent.rung() | nil,
          tracking: TrackingDetail.t() | nil,
          acquisition?: boolean(),
          lower_quality_accepted?: boolean(),
          complete?: boolean(),
          release_window: ReleaseWindow.t() | nil,
          planning_mode: PlanningMode.mode(),
          activity: Activities.activity_row() | nil,
          intent_note: String.t() | nil,
          friend_activity: [Activities.activity_row()],
          preview: TitlePreview.t() | nil
        }
end
