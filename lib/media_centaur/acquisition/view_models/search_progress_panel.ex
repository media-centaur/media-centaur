defmodule MediaCentaur.Acquisition.ViewModels.SearchProgressPanel do
  @moduledoc """
  The plan board's expectation panel: renders a
  `PlanEvents.SearchProgress` snapshot into one row per search step
  (what to expect from it). The board's headline for a planning plan is
  `ViewModels.GapVerdict`'s `:searching` world — one sentence-maker per
  board (UIDR-029) — so this panel never headlines. Pure — the LiveView
  only assigns the built view (ADR-030). `initial/1` covers the moment
  before the first broadcast lands.
  """

  alias MediaCentaur.Acquisition.PlanEvents.SearchProgress

  import MediaCentaur.Acquisition.ViewModels.Formatting, only: [count: 2]

  defmodule Row do
    @moduledoc "One search step in the expectation panel."

    @enforce_keys [:scope, :kind, :state, :label, :detail]
    defstruct [:scope, :kind, :state, :label, :detail]

    @type t :: %__MODULE__{
            scope: SearchProgress.scope(),
            kind: SearchProgress.kind(),
            state: SearchProgress.state(),
            label: String.t(),
            detail: String.t()
          }
  end

  defmodule View do
    @moduledoc "The built panel: one row per search step."

    @enforce_keys [:rows]
    defstruct [:rows]

    @type t :: %__MODULE__{rows: [Row.t()]}
  end

  @pending_steps [
    %{scope: :series, kind: :primary, state: :pending, term_count: nil, residual_after: nil},
    %{scope: :season, kind: :primary, state: :pending, term_count: nil, residual_after: nil},
    %{scope: :episode, kind: :primary, state: :pending, term_count: nil, residual_after: nil}
  ]

  @doc "The pre-event itinerary — expectations before the first broadcast."
  @spec initial(pos_integer()) :: View.t()
  def initial(wanted) do
    build(%SearchProgress{plan_id: nil, wanted: wanted, steps: @pending_steps})
  end

  @doc "Renders one full snapshot into the panel view."
  @spec build(SearchProgress.t()) :: View.t()
  def build(%SearchProgress{} = progress) do
    %View{rows: rows(progress)}
  end

  # -- rows -------------------------------------------------------------------

  defp rows(%SearchProgress{steps: steps, wanted: wanted}) do
    steps
    |> Enum.map_reduce(wanted, fn step, residual_before ->
      row = %Row{
        scope: step.scope,
        kind: step.kind,
        state: step.state,
        label: label(step.scope),
        detail: detail(step, residual_before)
      }

      {row, step.residual_after || residual_before}
    end)
    |> elem(0)
  end

  defp label(:series), do: "Complete series"
  defp label(:season), do: "Season packs"
  defp label(:episode), do: "Individual episodes"

  defp detail(%{state: :pending, scope: :series}, _residual), do: "one search for an all-in-one release"

  defp detail(%{state: :pending, scope: :season}, _residual),
    do: "packs for whatever the series search leaves uncovered"

  defp detail(%{state: :pending, scope: :episode}, _residual),
    do: "single episodes, only for what's still missing"

  defp detail(%{state: :active, term_count: terms}, _residual),
    do: "searching — #{count(terms, "term")}…"

  defp detail(%{state: :done, residual_after: 0}, _residual), do: "covered everything that was left"

  defp detail(%{state: :done, residual_after: still_missing}, residual_before) do
    case residual_before - still_missing do
      0 -> "nothing usable found"
      covered -> "covered #{count(covered, "episode")} — #{still_missing} still missing"
    end
  end

  defp detail(%{state: :skipped}, _residual), do: "not needed — already covered"
end
