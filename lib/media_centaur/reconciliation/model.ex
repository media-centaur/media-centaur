defmodule MediaCentaur.Reconciliation.Model do
  @moduledoc """
  The behaviour every interpretation model implements (reconciliation
  campaign). A model proposes how the unplaced `artifacts` map onto the
  canonical `spine`, given which nodes are already present. Pure — no I/O,
  no DB; the caller assembles the spine (one TMDB fetch + library
  present-set) and every model reads it.

  A model returns zero or more `Interpretation`s and **abstains** (returns
  `[]`) when it has no signal to offer — gap-fill is the reliable floor
  that always proposes when there's a gap; title/absolute/offset models
  abstain when their signal is absent. None is authoritative; the engine
  merges agreement and surfaces disagreement.
  """

  alias MediaCentaur.Reconciliation.{Artifact, Interpretation, SpineNode}

  @callback propose([SpineNode.t()], [Artifact.t()]) :: [Interpretation.t()]
end
