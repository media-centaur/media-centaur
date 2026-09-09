defmodule MediaCentaurWeb.Components.Title.Detail do
  @moduledoc """
  The title detail modal's view-model (UIDR-035): one TMDB title without
  files — watchlisted, tracked, in flight, or merely recommended — with
  the facts the modal's controls depend on already decided. Built by
  `DiscoveryLive.Logic.title_detail/2` from facts the
  `TitleDetailHost` resolved; rendered by `TitleDetailModal`.

  `primary` is the one honest primary action for the title's state:
  `{:in_library, owner_id}` (links to the library detail), `{:state,
  acquisition_state}` (Planning / Downloading / Needs review — a fact,
  not a verb), `:download`, or `nil` when there is nothing to download
  yet — the tracking-mode control is the arming surface, so there is
  no `Track` verb (ADR-065). `scoped?` says the download carries the
  series scope menu.

  `tracking` is the tracked-title half (`TrackingDetail`): nil for a
  title that has never been tracked. `acquisition?` and
  `default_grab_mode` are what the tracking-mode control needs to say
  honestly what each mode does right now.

  `friend_activity` is the title's `Activities.friend_activity_for/1`
  rows — the hero's pennants, the one place who-did-what shows
  (UIDR-037). `note` is the one thing a pennant cannot hold: a friend's
  words with the recommendation, attributed to `sender`, or the person's
  own watchlist note when `sender` is nil. `activity_id`, `own?` and
  `kind` name the activity the modal speaks for — a friend's, so that
  listing the title records where it came from; an own one, opened from
  the You card, so that Delete <noun> can withdraw it. All nil on a
  detail without one.

  `preview` is the live TMDB-backed `Detail.TitlePreview` the host
  fetches on open; nil until it lands, or when TMDB is not configured,
  in which case the modal dresses itself from the snapshot and the
  local artwork cache alone.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail

  @enforce_keys [:ref, :title, :primary, :scoped?]
  defstruct [
    :ref,
    :title,
    :poster_url,
    :backdrop_url,
    :logo_url,
    :primary,
    :scoped?,
    :rung,
    :tracking,
    :kind,
    :sender,
    :note,
    :own?,
    :activity_id,
    :preview,
    acquisition?: false,
    lower_quality_accepted?: false,
    default_grab_mode: "off",
    friend_activity: []
  ]

  @type primary ::
          {:in_library, Ecto.UUID.t()}
          | {:state, :planning | :downloading | :needs_review}
          | :download
          | nil

  @type t :: %__MODULE__{
          ref: {integer(), Title.media_type()},
          title: Title.t(),
          poster_url: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil,
          primary: primary(),
          scoped?: boolean(),
          rung: MediaCentaur.Discovery.TitleIntent.rung() | nil,
          tracking: TrackingDetail.t() | nil,
          acquisition?: boolean(),
          lower_quality_accepted?: boolean(),
          default_grab_mode: String.t(),
          kind: Activity.kind() | nil,
          sender: String.t() | nil,
          note: String.t() | nil,
          own?: boolean() | nil,
          activity_id: Ecto.UUID.t() | nil,
          friend_activity: [map()],
          preview: TitlePreview.t() | nil
        }
end
