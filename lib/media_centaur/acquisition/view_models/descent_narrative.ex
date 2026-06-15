defmodule MediaCentaur.Acquisition.ViewModels.DescentNarrative do
  @moduledoc """
  The plan board's expectation panel: renders a
  `PlanEvents.DescentStatus` snapshot into a headline (what's
  happening / what changed) plus one row per ladder rung (what to
  expect from it). Pure — the LiveView only assigns the built view
  (ADR-030). `initial/1` covers the moment before the first broadcast
  lands, so the board narrates the strategy from its first paint.
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
    @moduledoc "The built panel: headline plus rung rows."

    @enforce_keys [:headline, :rows]
    defstruct [:headline, :rows]

    @type t :: %__MODULE__{headline: String.t(), rows: [Row.t()]}
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
    %View{headline: headline(status), rows: rows(status)}
  end

  # -- headline ---------------------------------------------------------------

  defp headline(%DescentStatus{stages: stages, wanted: wanted}) do
    cond do
      active = Enum.find(stages, &(&1.state == :active)) ->
        active_headline(active.id, residual_before_active(stages, wanted))

      Enum.all?(stages, &(&1.state == :pending)) ->
        "Planning the search — broadest releases first, drilling down only for what's still missing."

      true ->
        finished_headline(stages)
    end
  end

  defp active_headline(:series, _residual),
    do: "First, looking for one release that covers the whole show…"

  defp active_headline(:seasons, residual),
    do: "Now searching season packs — #{count(residual, "episode")} still #{need(residual)} coverage…"

  defp active_headline(:episodes, residual),
    do: "Now hunting individual episodes — #{count(residual, "episode")} still uncovered…"

  defp finished_headline(stages) do
    last_done = stages |> Enum.filter(&(&1.state == :done)) |> List.last()
    skipped? = Enum.any?(stages, &(&1.state == :skipped))

    case {last_done, skipped?} do
      {%{residual_after: 0}, true} ->
        "Everything covered — the deeper searches weren't needed."

      {%{residual_after: 0}, false} ->
        "Everything covered."

      {%{residual_after: missing}, _} ->
        "Search finished — #{count(missing, "episode")} couldn't be found anywhere."

      {nil, _} ->
        "Search finished."
    end
  end

  defp residual_before_active(stages, wanted) do
    stages
    |> Enum.take_while(&(&1.state != :active))
    |> Enum.filter(&(&1.state == :done))
    |> List.last()
    |> case do
      nil -> wanted
      %{residual_after: residual} -> residual
    end
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

  defp need(1), do: "needs"
  defp need(_quantity), do: "need"
end
