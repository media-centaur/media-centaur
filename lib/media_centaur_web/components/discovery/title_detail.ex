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
  carries the series scope menu. `sender`, `note`, `recommended_at` and
  `own?` are the feed provenance and nil on a watchlist-born detail
  without one; `sender` is nil on an own recommendation (the modal
  reads `own?`).
  """

  alias MediaCentaur.TMDB.Title

  @enforce_keys [:ref, :title, :primary, :scoped?, :on_watchlist?]
  defstruct [
    :ref,
    :title,
    :poster_url,
    :backdrop_url,
    :primary,
    :scoped?,
    :on_watchlist?,
    :sender,
    :note,
    :recommended_at,
    :own?,
    :recommendation_id
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
          sender: String.t() | nil,
          note: String.t() | nil,
          recommended_at: DateTime.t() | nil,
          own?: boolean() | nil,
          recommendation_id: Ecto.UUID.t() | nil
        }
end
