defmodule MediaCentaur.Acquisition.ViewModels.PursuitHeader do
  @moduledoc "Identity contract for the detail-page header."

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaur.Acquisition.Pursuits.Recipe

  @enforce_keys [:id, :title, :state, :recipe]
  defstruct [
    :id,
    :title,
    :state,
    :recipe,
    :criteria_summary,
    :backdrop_url,
    :logo_url,
    awaiting_decision?: false,
    search_queries: []
  ]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          state: PursuitRow.state(),
          recipe: Recipe.t(),
          # Prowlarr query strings this pursuit would search with (from
          # `Acquisition.QueryBuilder`) — the recipe is the *what*, this is the
          # *how it's searched*. Surfaced verbatim by the detail UI.
          search_queries: [String.t()],
          criteria_summary: String.t() | nil,
          backdrop_url: String.t() | nil,
          logo_url: String.t() | nil,
          awaiting_decision?: boolean()
        }
end
