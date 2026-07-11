defmodule MediaCentaurWeb.Components.Upcoming.MonthGridTest do
  @moduledoc "Pure calendar-grid math for the mini-month companion."
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Upcoming.MonthGrid

  describe "weeks/2" do
    test "every week has exactly seven cells" do
      for week <- MonthGrid.weeks(2026, 6) do
        assert length(week) == 7
      end
    end

    test "contains every day of the month exactly once and nothing from other months" do
      days =
        2026
        |> MonthGrid.weeks(6)
        |> List.flatten()
        |> Enum.reject(&is_nil/1)

      assert length(days) == 30
      assert Enum.all?(days, &(&1.month == 6 and &1.year == 2026))
      assert ~D[2026-06-01] in days
      assert ~D[2026-06-30] in days
    end

    test "leads with nil padding so the first day lands on its weekday column" do
      # 2026-06-01 is a Monday; weeks start Monday → no leading padding.
      [first_week | _] = MonthGrid.weeks(2026, 6)
      assert hd(first_week) == ~D[2026-06-01]

      # 2026-07-01 is a Wednesday → two leading nils (Mon, Tue).
      [july_first_week | _] = MonthGrid.weeks(2026, 7)
      assert [nil, nil, ~D[2026-07-01] | _] = july_first_week
    end
  end
end
