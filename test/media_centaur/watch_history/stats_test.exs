defmodule MediaCentaur.WatchHistory.StatsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.WatchHistory.Stats

  # `streak_from_dates/1` takes the distinct completion dates the database
  # already grouped, newest first. The same-day collapse is SQL's job and is
  # asserted against the real query in `watch_history_test.exs`.
  describe "streak_from_dates/1" do
    test "returns 0 for empty list" do
      assert Stats.streak_from_dates([]) == 0
    end

    test "counts consecutive days ending today" do
      today = Date.utc_today()
      assert Stats.streak_from_dates([today, Date.add(today, -1)]) == 2
    end

    test "yesterday alone keeps streak at 1 (grace period)" do
      assert Stats.streak_from_dates([Date.add(Date.utc_today(), -1)]) == 1
    end

    test "breaks on a gap" do
      today = Date.utc_today()
      assert Stats.streak_from_dates([today, Date.add(today, -2)]) == 1
    end
  end

  describe "heatmap_cells/1" do
    test "returns 364 cells covering last 52 weeks" do
      cells = Stats.heatmap_cells(%{})
      assert length(cells) == 364
    end

    test "each cell has :date, :count, :x, :y" do
      [cell | _] = Stats.heatmap_cells(%{})
      assert Map.has_key?(cell, :date)
      assert Map.has_key?(cell, :count)
      assert Map.has_key?(cell, :x)
      assert Map.has_key?(cell, :y)
    end

    test "last cell is today" do
      cells = Stats.heatmap_cells(%{})
      last = List.last(cells)
      assert last.date == Date.utc_today()
    end

    test "populates count from heatmap data" do
      today = Date.utc_today()
      cells = Stats.heatmap_cells(%{today => 5})
      last = List.last(cells)
      assert last.count == 5
    end
  end
end
