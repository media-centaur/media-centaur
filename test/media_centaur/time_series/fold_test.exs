defmodule MediaCentaur.TimeSeries.FoldTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.{Fold, LocalDay, Schema, Store}

  @schema Schema.new(requests: :sum, failed: :sum, latency_max_ms: :max)
  # 2026-09-19 13:26:17 UTC
  @now 1_789_824_377

  setup do
    suffix = System.unique_integer([:positive])
    table = :"fold_table_#{suffix}"
    start_supervised!({Store, name: :"fold_store_#{suffix}", table: table, schema: @schema})
    %{table: table}
  end

  test "a 1h window is 60 one-minute buckets ending at the current minute, zero-filled",
       %{table: table} do
    Store.add(table, @schema, :tmdb, @now - 120, %{requests: 3, failed: 1, latency_max_ms: 300})
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 90})

    series = Fold.series(table, @schema, :tmdb, :"1h", @now, utc_offset: 0)

    assert length(series.starts) == 60
    assert List.last(series.starts) == @now - rem(@now, 60)
    assert hd(series.starts) == List.last(series.starts) - 59 * 60
    assert series.bar_seconds == 60
    assert Enum.sum(series.columns.requests) == 4
    assert Enum.at(series.columns.requests, 57) == 3
    assert Enum.at(series.columns.failed, 57) == 1
    assert Enum.at(series.columns.latency_max_ms, 57) == 300
    assert List.last(series.columns.requests) == 1
    assert series.totals == %{requests: 4, failed: 1, latency_max_ms: 300}
  end

  test "a 5h window sums five one-minute rows into each bar", %{table: table} do
    for offset <- 0..4 do
      Store.add(table, @schema, :tmdb, @now - offset * 60, %{
        requests: 1,
        failed: 0,
        latency_max_ms: 1
      })
    end

    series = Fold.series(table, @schema, :tmdb, :"5h", @now, utc_offset: 0)

    assert length(series.starts) == 60
    assert series.bar_seconds == 300
    assert Enum.sum(series.columns.requests) == 5
    # the five minutes straddle at most two 5-minute bars
    assert series.columns.requests |> Enum.reverse() |> Enum.take(2) |> Enum.sum() == 5
  end

  test "wide bars start on the local midnight given by the offset", %{table: table} do
    two_hours_east = 2 * 3_600
    series = Fold.series(table, @schema, :tmdb, :"1mo", @now, utc_offset: two_hours_east)

    local_midnight = LocalDay.start_of_day(@now, two_hours_east)
    assert rem(local_midnight + two_hours_east, 86_400) == 0
    assert Enum.all?(series.starts, &(rem(&1 - local_midnight, 43_200) == 0))
    assert List.last(series.starts) <= @now
    assert List.last(series.starts) + 43_200 > @now
  end

  test "a series with no rows is all zeros", %{table: table} do
    series = Fold.series(table, @schema, :github, :"5m", @now, utc_offset: 0)
    assert length(series.starts) == 30
    assert Enum.all?(series.columns.requests, &(&1 == 0))
    assert series.totals == %{requests: 0, failed: 0, latency_max_ms: 0}
  end

  test "LocalDay.start_of_day is the midnight before `unix` in the offset zone" do
    # 13:26:17 UTC at +02:00 is 15:26:17 local; local midnight is 22:00 UTC the day before.
    assert LocalDay.start_of_day(@now, 7_200) == @now - (15 * 3_600 + 26 * 60 + 17)
    # at -05:00 it is 08:26:17 local; local midnight is 05:00 UTC the same day.
    assert LocalDay.start_of_day(@now, -18_000) == @now - (8 * 3_600 + 26 * 60 + 17)
  end

  test "LocalDay.utc_offset_seconds is a whole number of minutes within a day" do
    offset = LocalDay.utc_offset_seconds()
    assert rem(offset, 60) == 0
    assert abs(offset) < 86_400
  end
end
