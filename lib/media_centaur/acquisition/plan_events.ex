defmodule MediaCentaur.Acquisition.PlanEvents do
  @moduledoc """
  Transient broadcast structs for draft-plan progress, published on
  `acquisition:updates` alongside the target/pursuit events.

  Plan progress is **not** a persisted timeline — the durable plan rows
  themselves are the state of record; these structs only tell live
  subscribers (the planning board, the Downloads page) to re-read.
  Pursuit-level history starts at commit, when the composite pursuit's
  own event log takes over.
  """

  defmodule Changed do
    @moduledoc "The plan's rows changed (status, a search landed, an assignment moved) — re-read."

    @enforce_keys [:plan_id, :status]
    defstruct [:plan_id, :status]

    @type t :: %__MODULE__{plan_id: Ecto.UUID.t(), status: String.t()}
  end

  defmodule SearchActivity do
    @moduledoc "One search term ran (live activity feed fodder): the term and how it resolved."

    @enforce_keys [:plan_id, :term, :outcome]
    defstruct [:plan_id, :term, :outcome, result_count: 0]

    @type t :: %__MODULE__{
            plan_id: Ecto.UUID.t(),
            term: String.t(),
            outcome: :corpus | :live | :error,
            result_count: non_neg_integer()
          }
  end

  defmodule SearchProgress do
    @moduledoc """
    Itinerary snapshot of a TV plan's search: every step — one scope
    (series, season, episode) searched for one purpose — with its
    state, so the board can narrate what will happen, what's happening,
    and what changed. A `:primary` step may assign what it finds; a
    `:fallback` step only gathers packs to offer. Each broadcast carries
    the FULL snapshot — subscribers replace, never merge, so a modal
    opened mid-run self-heals on the next event.
    """

    @enforce_keys [:plan_id, :wanted, :steps]
    defstruct [:plan_id, :wanted, :steps]

    @type scope :: :series | :season | :episode
    @type kind :: :primary | :fallback
    @type state :: :pending | :active | :done | :skipped

    @type step :: %{
            scope: scope(),
            kind: kind(),
            state: state(),
            term_count: non_neg_integer() | nil,
            residual_after: non_neg_integer() | nil
          }

    @type t :: %__MODULE__{
            plan_id: Ecto.UUID.t() | nil,
            wanted: pos_integer(),
            steps: [step()]
          }
  end
end
