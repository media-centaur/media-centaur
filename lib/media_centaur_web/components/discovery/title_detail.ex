defmodule MediaCentaurWeb.Components.Discovery.TitleDetail do
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

  `kind`, `episode`, `sender`, `note`, `acted_at` and `own?` are the
  feed provenance and nil on a detail without one; `sender` is nil on
  an own activity (the modal reads `own?`), `episode` is set on a
  watched series only. `recommendations` are the title's
  `Activities.recommendations_for/1` rows for the hero's pennants.

  `preview` is the live TMDB-backed `Detail.TitlePreview` the host
  fetches on open; nil until it lands, or when TMDB is not configured,
  in which case the modal dresses itself from the snapshot and the
  local artwork cache alone.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.TitlePreview
  alias MediaCentaurWeb.Components.ReleaseTracking.TrackingDetail

  @enforce_keys [:ref, :title, :primary, :scoped?, :on_watchlist?]
  defstruct [
    :ref,
    :title,
    :poster_url,
    :backdrop_url,
    :logo_url,
    :primary,
    :scoped?,
    :on_watchlist?,
    :tracking,
    :kind,
    :episode,
    :sender,
    :note,
    :acted_at,
    :own?,
    :activity_id,
    :preview,
    acquisition?: false,
    default_grab_mode: "off",
    recommendations: []
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
          on_watchlist?: boolean(),
          tracking: TrackingDetail.t() | nil,
          acquisition?: boolean(),
          default_grab_mode: String.t(),
          kind: Activity.kind() | nil,
          episode: Episode.t() | nil,
          sender: String.t() | nil,
          note: String.t() | nil,
          acted_at: DateTime.t() | nil,
          own?: boolean() | nil,
          activity_id: Ecto.UUID.t() | nil,
          recommendations: [map()],
          preview: TitlePreview.t() | nil
        }
end
