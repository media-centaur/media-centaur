defmodule MediaCentaur.Acquisition.ViewModels.DecisionCard do
  @moduledoc "Display contract for the alternatives picker."

  alias MediaCentaur.Acquisition.ViewModels.Alternative

  @enforce_keys [:pursuit_id, :prompt, :alternatives]
  defstruct [:pursuit_id, :prompt, :alternatives, :loading?, :left_out, search_queries: []]

  @typedoc """
  - `search_queries` — the ordered list of Prowlarr query strings that
    produced (or will reproduce, on Search again) the alternatives.
    Same list as `Recipe.search_queries` for the pursuit; carried on
    the card so the decision UI can show the literal queries inline
    with the prompt without re-deriving them.
  - `left_out` — one sentence counting the releases the search found
    and the card does not list, by reason (`Rejection.summary/1`); nil
    when it lists everything it found.
  """
  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          prompt: String.t(),
          alternatives: [Alternative.t()],
          loading?: boolean(),
          left_out: String.t() | nil,
          search_queries: [String.t()]
        }
end
