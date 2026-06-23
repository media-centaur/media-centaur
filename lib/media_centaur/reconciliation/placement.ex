defmodule MediaCentaur.Reconciliation.Placement do
  @moduledoc """
  A proposed link from an artifact to a canonical spine node
  (`{season, episode}`). The atom of an `Interpretation` — confirming an
  interpretation turns its placements into real file↔episode links, never
  fabricated structure (reconciliation campaign).
  """

  @enforce_keys [:artifact_id, :season, :episode]
  defstruct [:artifact_id, :season, :episode]

  @type t :: %__MODULE__{artifact_id: String.t(), season: integer(), episode: integer()}
end
