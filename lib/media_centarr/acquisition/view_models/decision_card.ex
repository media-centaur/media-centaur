defmodule MediaCentarr.Acquisition.ViewModels.DecisionCard do
  @moduledoc "Display contract for the alternatives picker."

  alias MediaCentarr.Acquisition.ViewModels.Alternative

  @enforce_keys [:pursuit_id, :prompt, :alternatives]
  defstruct [:pursuit_id, :prompt, :alternatives, :loading?, search_queries: []]

  @typedoc """
  - `search_queries` — the ordered list of Prowlarr query strings that
    produced (or will reproduce, on Search again) the alternatives.
    Same list as `Recipe.search_queries` for the pursuit; carried on
    the card so the decision UI can show the literal queries inline
    with the prompt without re-deriving them.
  """
  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          prompt: String.t(),
          alternatives: [Alternative.t()],
          loading?: boolean(),
          search_queries: [String.t()]
        }
end
