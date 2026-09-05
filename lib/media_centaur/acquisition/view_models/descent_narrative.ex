defmodule MediaCentaur.Acquisition.ViewModels.DescentNarrative do
  @moduledoc """
  The plan board's expectation panel: renders a
  `PlanEvents.DescentStatus` snapshot into one row per ladder rung
  (what to expect from it). The board's headline for a planning plan is
  `ViewModels.GapVerdict`'s `:searching` world — one sentence-maker per
  board (UIDR-029) — so this panel never headlines. Pure — the LiveView
  only assigns the built view (ADR-030). `initial/1` covers the moment
  before the first broadcast lands.
  """

  alias MediaCentaur.Acquisition.PlanEvents.DescentStatus

  import MediaCentaur.Acquisition.ViewModels.Formatting, only: [count: 2]

  defmodule Row do
    @moduledoc "One ladder rung in the expectation panel."

    @enforce_keys [:id, :state, :label, :detail]
    defstruct [:id, :state, :label, :detail]

    @type t :: %__MODULE__{
            id: :series | :seasons | :episodes,
            state: :pending | :active | :done | :skipped,
            label: String.t(),
            detail: String.t()
          }
  end

  defmodule View do
    @moduledoc "The built panel: the rung rows."

    @enforce_keys [:rows]
    defstruct [:rows]

    @type t :: %__MODULE__{rows: [Row.t()]}
  end

  @pending_stages [
    %{id: :series, state: :pending, term_count: nil, residual_after: nil},
    %{id: :seasons, state: :pending, term_count: nil, residual_after: nil},
    %{id: :episodes, state: :pending, term_count: nil, residual_after: nil}
  ]

  @doc "The pre-event itinerary — expectations before the first broadcast."
  @spec initial(pos_integer()) :: View.t()
  def initial(wanted) do
    build(%DescentStatus{plan_id: nil, wanted: wanted, stages: @pending_stages})
  end

  @doc "Renders one full snapshot into the panel view."
  @spec build(DescentStatus.t()) :: View.t()
  def build(%DescentStatus{} = status) do
    %View{rows: rows(status)}
  end

  # -- rows -------------------------------------------------------------------

  defp rows(%DescentStatus{stages: stages, wanted: wanted}) do
    stages
    |> Enum.map_reduce(wanted, fn stage, residual_before ->
      row = %Row{
        id: stage.id,
        state: stage.state,
        label: label(stage.id),
        detail: detail(stage, residual_before)
      }

      {row, stage.residual_after || residual_before}
    end)
    |> elem(0)
  end

  defp label(:series), do: "Complete series"
  defp label(:seasons), do: "Season packs"
  defp label(:episodes), do: "Individual episodes"

  defp detail(%{state: :pending, id: :series}, _residual), do: "one search for an all-in-one release"

  defp detail(%{state: :pending, id: :seasons}, _residual),
    do: "packs for whatever the series rung leaves uncovered"

  defp detail(%{state: :pending, id: :episodes}, _residual),
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
