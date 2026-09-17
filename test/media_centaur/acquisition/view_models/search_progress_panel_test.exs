defmodule MediaCentaur.Acquisition.ViewModels.SearchProgressPanelTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.PlanEvents.SearchProgress
  alias MediaCentaur.Acquisition.ViewModels.SearchProgressPanel

  defp step(scope, state, attrs \\ []) do
    %{
      scope: scope,
      kind: Keyword.get(attrs, :kind, :primary),
      state: state,
      term_count: Keyword.get(attrs, :term_count),
      residual_after: Keyword.get(attrs, :residual_after)
    }
  end

  defp status(steps, wanted), do: %SearchProgress{plan_id: "plan-1", wanted: wanted, steps: steps}

  test "initial/1 narrates the strategy before any event lands" do
    view = SearchProgressPanel.initial(24)

    assert Enum.map(view.rows, &{&1.scope, &1.state}) ==
             [series: :pending, season: :pending, episode: :pending]

    assert Enum.map(view.rows, & &1.label) ==
             ["Complete series", "Season packs", "Individual episodes"]
  end

  test "an active step says what's happening with the live residual" do
    view =
      SearchProgressPanel.build(
        status(
          [
            step(:series, :done, residual_after: 4),
            step(:season, :active, term_count: 4),
            step(:episode, :pending)
          ],
          24
        )
      )

    assert Enum.find(view.rows, &(&1.scope == :season)).detail == "searching — 4 terms…"
  end

  test "a done step's detail says what it changed" do
    view =
      SearchProgressPanel.build(
        status(
          [
            step(:series, :done, residual_after: 24),
            step(:season, :done, residual_after: 1),
            step(:episode, :active, term_count: 1)
          ],
          24
        )
      )

    rows = Map.new(view.rows, &{&1.scope, &1.detail})
    assert rows[:series] == "nothing usable found"
    assert rows[:season] == "covered 23 episodes — 1 still missing"
  end

  test "a finished search with skipped steps explains the early stop" do
    view =
      SearchProgressPanel.build(
        status(
          [
            step(:series, :done, residual_after: 24),
            step(:season, :done, residual_after: 0),
            step(:episode, :skipped)
          ],
          24
        )
      )

    assert Enum.find(view.rows, &(&1.scope == :episode)).detail == "not needed — already covered"
    assert Enum.find(view.rows, &(&1.scope == :season)).detail == "covered everything that was left"
  end

  test "a finished search with leftovers reports the gap" do
    view =
      SearchProgressPanel.build(
        status(
          [
            step(:series, :done, residual_after: 4),
            step(:season, :done, residual_after: 2),
            step(:episode, :done, residual_after: 2)
          ],
          4
        )
      )

    assert Enum.find(view.rows, &(&1.scope == :episode)).detail == "nothing usable found"
  end
end
