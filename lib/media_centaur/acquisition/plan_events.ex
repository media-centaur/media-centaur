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
    @moduledoc "One ladder search ran (live activity feed fodder): the term and how it resolved."

    @enforce_keys [:plan_id, :term, :outcome]
    defstruct [:plan_id, :term, :outcome, result_count: 0]

    @type t :: %__MODULE__{
            plan_id: Ecto.UUID.t(),
            term: String.t(),
            outcome: :corpus | :live | :error,
            result_count: non_neg_integer()
          }
  end

  @doc "True when the struct is one of this module's event kinds."
  def event?(Changed), do: true
  def event?(SearchActivity), do: true
  def event?(_module), do: false
end
