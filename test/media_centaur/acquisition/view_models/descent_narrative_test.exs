defmodule MediaCentaur.Acquisition.ViewModels.DescentNarrativeTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.PlanEvents.DescentStatus
  alias MediaCentaur.Acquisition.ViewModels.DescentNarrative

  defp stage(id, state, attrs \\ []) do
    %{
      id: id,
      state: state,
      term_count: Keyword.get(attrs, :term_count),
      residual_after: Keyword.get(attrs, :residual_after)
    }
  end

  defp status(stages, wanted), do: %DescentStatus{plan_id: "plan-1", wanted: wanted, stages: stages}

  test "initial/1 narrates the strategy before any event lands" do
    view = DescentNarrative.initial(24)

    assert Enum.map(view.rows, &{&1.id, &1.state}) ==
             [series: :pending, seasons: :pending, episodes: :pending]

    assert Enum.map(view.rows, & &1.label) ==
             ["Complete series", "Season packs", "Individual episodes"]
  end

  test "an active rung headlines what's happening with the live residual" do
    view =
      DescentNarrative.build(
        status(
          [
            stage(:series, :done, residual_after: 4),
            stage(:seasons, :active, term_count: 4),
            stage(:episodes, :pending)
          ],
          24
        )
      )

    assert Enum.find(view.rows, &(&1.id == :seasons)).detail == "searching — 4 terms…"
  end

  test "a done rung's detail says what it changed" do
    view =
      DescentNarrative.build(
        status(
          [
            stage(:series, :done, residual_after: 24),
            stage(:seasons, :done, residual_after: 1),
            stage(:episodes, :active, term_count: 1)
          ],
          24
        )
      )

    rows = Map.new(view.rows, &{&1.id, &1.detail})
    assert rows[:series] == "nothing usable found"
    assert rows[:seasons] == "covered 23 episodes — 1 still missing"
  end

  test "a finished descent with skipped rungs explains the early stop" do
    view =
      DescentNarrative.build(
        status(
          [
            stage(:series, :done, residual_after: 24),
            stage(:seasons, :done, residual_after: 0),
            stage(:episodes, :skipped)
          ],
          24
        )
      )

    assert Enum.find(view.rows, &(&1.id == :episodes)).detail == "not needed — already covered"
    assert Enum.find(view.rows, &(&1.id == :seasons)).detail == "covered everything that was left"
  end

  test "a finished descent with leftovers reports the gap" do
    view =
      DescentNarrative.build(
        status(
          [
            stage(:series, :done, residual_after: 4),
            stage(:seasons, :done, residual_after: 2),
            stage(:episodes, :done, residual_after: 2)
          ],
          4
        )
      )

    assert Enum.find(view.rows, &(&1.id == :episodes)).detail == "nothing usable found"
  end
end
