defmodule MediaCentaur.Reconciliation.Interpretation do
  @moduledoc """
  One model's complete proposal for how a batch of artifacts maps onto the
  spine: the `placements`, a `confidence` (0.0–1.0), a `model` tag, and a
  human-readable `rationale` for the confirmation surface (reconciliation
  campaign). Models that agree are collapsed; models that disagree surface
  as alternatives the user arbitrates.
  """

  alias MediaCentaur.Reconciliation.Placement

  @enforce_keys [:model, :placements, :confidence, :rationale]
  defstruct [:model, :placements, :confidence, :rationale]

  @type t :: %__MODULE__{
          model: atom(),
          placements: [Placement.t()],
          confidence: float(),
          rationale: String.t()
        }
end
