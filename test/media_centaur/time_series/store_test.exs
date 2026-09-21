defmodule MediaCentaur.TimeSeries.StoreTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.TimeSeries.{Resolution, Schema, Store}

  @schema Schema.new(requests: :sum, failed: :sum, latency_max_ms: :max)
  @now 1_789_800_017

  setup do
    suffix = System.unique_integer([:positive])
    name = :"time_series_store_test_#{suffix}"
    table = :"time_series_store_table_#{suffix}"
    start_supervised!({Store, name: name, table: table, schema: @schema})
    %{name: name, table: table}
  end

  test "add lands in all four resolutions at their bucket starts", %{table: table} do
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 180})

    for resolution <- Resolution.all() do
      start = Resolution.bucket_start(resolution, @now)

      assert [{^start, %{requests: 1, failed: 0, latency_max_ms: 180}}] =
               Store.rows(table, resolution, :tmdb, start, @now)
    end
  end

  test "sums accumulate and maxima keep the largest", %{table: table} do
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 1, latency_max_ms: 500})
    Store.add(table, @schema, :tmdb, @now + 1, %{requests: 1, failed: 0, latency_max_ms: 120})

    assert [{_, %{requests: 2, failed: 1, latency_max_ms: 500}}] =
             Store.rows(table, :"10s", :tmdb, @now - 10, @now + 1)
  end

  test "rows are per key and sorted ascending within the asked span", %{table: table} do
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 1})
    Store.add(table, @schema, :tmdb, @now + 60, %{requests: 2, failed: 0, latency_max_ms: 1})
    Store.add(table, @schema, :github, @now, %{requests: 9, failed: 0, latency_max_ms: 1})

    assert [{first, %{requests: 1}}, {second, %{requests: 2}}] =
             Store.rows(table, :"1m", :tmdb, @now - 60, @now + 60)

    assert first < second
    assert Store.rows(table, :"1m", :tmdb, @now + 61, @now + 120) == []
  end

  test "rows of a store that is not running are empty" do
    assert Store.rows(:no_such_table, :"1m", :tmdb, 0, @now) == []
  end

  test "sweep removes rows past each resolution's retention and reports the count",
       %{name: name, table: table} do
    old = @now - Resolution.retention(:"10s") - 20
    Store.add(table, @schema, :tmdb, old, %{requests: 1, failed: 0, latency_max_ms: 1})
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 1})

    # `old` is past the 10 s retention (1 h) but inside the 1 min retention (6 h).
    assert Store.sweep_now(name, @now) == 1
    assert length(Store.rows(table, :"10s", :tmdb, 0, @now)) == 1
    assert length(Store.rows(table, :"1m", :tmdb, 0, @now)) == 2
  end

  test "writes are counted so a snapshot can be skipped when nothing changed", %{table: table} do
    assert Store.writes(table) == 0
    Store.add(table, @schema, :tmdb, @now, %{requests: 1, failed: 0, latency_max_ms: 1})
    assert Store.writes(table) == 1
  end
end
