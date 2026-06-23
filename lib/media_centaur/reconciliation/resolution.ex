defmodule MediaCentaur.Reconciliation.Resolution do
  @moduledoc """
  The engine's verdict for one show's batch (reconciliation campaign). It
  maps the four placement states onto distinct fields rather than tagging
  each placement:

  - `recommended` — the synthesized best mapping for the unpinned batch (the
    `model: :recommended` interpretation), or `nil` when nothing could be
    placed. Whether it links silently or awaits the user is the `auto?` flag.
  - `alternatives` — the raw per-model interpretations, ranked by confidence,
    for the review surface (the collapsed alternative chips).
  - `pinned` — user-overridden placements the engine honored (models
    re-propose around them, never overturn).
  - `unplaced` — artifact ids no model could place (fully manual).
  - `auto?` — true only under the conservative rule: ≥2 models corroborate
    every recommended placement, the batch fills the gap exactly (1:1), and
    nothing is unplaced. Everything else is `proposed` (awaits the user).
  """

  alias MediaCentaur.Reconciliation.{Interpretation, Placement}

  defstruct recommended: nil, alternatives: [], pinned: [], unplaced: [], auto?: false

  @type t :: %__MODULE__{
          recommended: Interpretation.t() | nil,
          alternatives: [Interpretation.t()],
          pinned: [Placement.t()],
          unplaced: [String.t()],
          auto?: boolean()
        }
end
