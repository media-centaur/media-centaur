defmodule MediaCentaur.WatchHistory.StatsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.WatchHistory.{Event, Stats}

  defp make_event(date, duration_seconds \\ 7200.0) do
    %Event{
      completed_at: DateTime.new!(date, ~T[20:00:00], "Etc/UTC"),
      duration_seconds: duration_seconds
    }
  end

  describe "compute/1" do
    test "returns zeros for empty list" do
      assert Stats.compute([]) == %{
               total_count: 0,
               total_seconds: 0.0,
               streak: 0,
               heatmap: %{}
             }
    end

    test "sums count and seconds" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      events = [make_event(today, 7200.0), make_event(yesterday, 3600.0)]
      result = Stats.compute(events)
      assert result.total_count == 2
      assert result.total_seconds == 10_800.0
    end
  end

  describe "streak/1" do
    test "returns 0 for empty list" do
      assert Stats.streak([]) == 0
    end

    test "counts consecutive days ending today" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      events = [make_event(today), make_event(yesterday)]
      assert Stats.streak(events) == 2
    end

    test "yesterday alone keeps streak at 1 (grace period)" do
      yesterday = Date.add(Date.utc_today(), -1)
      events = [make_event(yesterday)]
      assert Stats.streak(events) == 1
    end

    test "breaks on a gap" do
      today = Date.utc_today()
      two_ago = Date.add(today, -2)
      events = [make_event(today), make_event(two_ago)]
      assert Stats.streak(events) == 1
    end

    test "multiple completions on same day count as one streak day" do
      today = Date.utc_today()
      events = [make_event(today), make_event(today), make_event(today)]
      assert Stats.streak(events) == 1
    end
  end

  describe "heatmap/1" do
    test "returns empty map for empty list" do
      assert Stats.heatmap([]) == %{}
    end

    test "counts completions per day" do
      date = Date.utc_today()
      events = [make_event(date), make_event(date)]
      assert Stats.heatmap(events)[date] == 2
    end

    test "excludes events older than 364 days" do
      old_date = Date.add(Date.utc_today(), -365)
      events = [make_event(old_date)]
      assert Stats.heatmap(events) == %{}
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
