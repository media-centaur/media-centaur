defmodule MediaCentaurWeb.Components.Discovery.TitleDetail do
  @moduledoc """
  The title detail modal's view-model (spec 2026-09-05 §12–13): one
  TMDB title the library does not own, with the facts the modal's
  actions depend on already decided. Built by `DiscoveryLive.Logic.
  title_detail/2`; rendered by `TitleDetailModal`.

  `primary` is the one honest primary action for the title's state:
  `{:in_library, owner_id}` (links to the library detail), `{:state,
  acquisition_state}` (Planning / Downloading / Needs review — a fact,
  not a verb), `:download`, or `:track`. `scoped?` says the download
  carries the series scope menu. `kind`, `episode`, `sender`, `note`,
  `acted_at` and `own?` are the feed provenance and nil on a
  watchlist-born detail without one; `sender` is nil on an own activity
  (the modal reads `own?`), `episode` is set on a watched series only.

  `recommendations` are the title's `Activities.recommendations_for/1`
  rows — every friend's (and an own) recommendation, for the hero's
  pennants; empty when nobody recommended it.

  `preview` is the live TMDB-backed `Detail.TitlePreview` (backdrop,
  logo, tagline, metadata, facets, cast) the host fetches on open; nil
  until it lands, or when TMDB is not configured, in which case the
  modal dresses itself from the snapshot alone.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Detail.TitlePreview

  @enforce_keys [:ref, :title, :primary, :scoped?, :on_watchlist?]
  defstruct [
    :ref,
    :title,
    :poster_url,
    :backdrop_url,
    :primary,
    :scoped?,
    :on_watchlist?,
    :kind,
    :episode,
    :sender,
    :note,
    :acted_at,
    :own?,
    :activity_id,
    :preview,
    recommendations: []
  ]

  @type primary ::
          {:in_library, Ecto.UUID.t()}
          | {:state, :planning | :downloading | :needs_review}
          | :download
          | :track

  @type t :: %__MODULE__{
          ref: {integer(), Title.media_type()},
          title: Title.t(),
          poster_url: String.t() | nil,
          backdrop_url: String.t() | nil,
          primary: primary(),
          scoped?: boolean(),
          on_watchlist?: boolean(),
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
