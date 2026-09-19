defmodule MediaCentaur.HttpClient.TrafficTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.HttpClient.Traffic
  alias MediaCentaur.TimeSeries.Store

  @stop_event [:media_centaur, :http, :request, :stop]
  @now 1_789_824_377

  setup do
    suffix = System.unique_integer([:positive])
    store = :"traffic_store_#{suffix}"
    recent = :"traffic_recent_#{suffix}"

    start_supervised!(
      {Store, name: :"traffic_store_name_#{suffix}", table: store, schema: Traffic.schema()},
      id: :store
    )

    start_supervised!(
      {Traffic, name: :"traffic_#{suffix}", attach: false, store_table: store, recent_table: recent},
      id: :traffic
    )

    %{tables: [store_table: store, recent_table: recent]}
  end

  defp record(tables, overrides) do
    metadata =
      Map.merge(
        %{
          upstream: :tmdb,
          method: :get,
          path: "/3/movie/1",
          status: 200,
          error: nil,
          cache: :miss
        },
        Map.drop(overrides, [:duration_ms, :at])
      )

    duration =
      System.convert_time_unit(Map.get(overrides, :duration_ms, 100), :millisecond, :native)

    config = %{
      store: tables[:store_table],
      recent: tables[:recent_table],
      now: Map.get(overrides, :at, @now)
    }

    Traffic.handle_telemetry(@stop_event, %{duration: duration}, metadata, config)
  end

  test "a request counts requests and latency; a failure counts failed too", %{tables: tables} do
    record(tables, %{duration_ms: 200})
    record(tables, %{status: 500, duration_ms: 400})

    totals = Traffic.totals(:tmdb, [seconds: 900, now: @now] ++ tables)
    assert totals == %{requests: 2, failed: 1, cached: 0, mean_ms: 300, worst_ms: 400}
  end

  test "a transport error is a failure", %{tables: tables} do
    record(tables, %{status: nil, error: %RuntimeError{message: "closed"}})
    assert %{requests: 1, failed: 1} = Traffic.totals(:tmdb, [seconds: 900, now: @now] ++ tables)
  end

  test "a cache hit counts only cached and leaves the last outcome alone", %{tables: tables} do
    record(tables, %{cache: :hit})

    assert Traffic.totals(:tmdb, [seconds: 900, now: @now] ++ tables) ==
             %{requests: 0, failed: 0, cached: 1, mean_ms: nil, worst_ms: nil}

    assert Traffic.last(:tmdb, tables) == nil
  end

  test "last outcome and last success follow requests", %{tables: tables} do
    record(tables, %{at: @now - 30})
    assert %{outcome: :ok, at: %DateTime{}} = Traffic.last(:tmdb, tables)
    record(tables, %{at: @now, status: 503})
    assert %{outcome: :failed} = Traffic.last(:tmdb, tables)
    assert DateTime.to_unix(Traffic.last_success_at(:tmdb, tables)) == @now - 30
  end

  test "series carries went_out, failed, cached, mean and worst per bar", %{tables: tables} do
    record(tables, %{duration_ms: 100})
    record(tables, %{duration_ms: 300, status: 502})

    series = Traffic.series(:tmdb, :"1h", [now: @now, utc_offset: 0] ++ tables)

    assert length(series.starts) == 60
    assert List.last(series.went_out) == 1
    assert List.last(series.failed) == 1
    assert List.last(series.cached) == 0
    assert List.last(series.mean_ms) == 200
    assert List.last(series.worst_ms) == 300
    assert Enum.at(series.mean_ms, 0) == nil
    assert series.totals == %{requests: 2, failed: 1, cached: 0, mean_ms: 200, worst_ms: 300}
  end

  test "recent keeps the newest twenty, newest first", %{tables: tables} do
    for n <- 1..25, do: record(tables, %{path: "/3/movie/#{n}", at: @now + n})

    recent = Traffic.recent(tables)
    assert length(recent) == 20
    assert hd(recent).path == "/3/movie/25"
    assert recent |> Enum.map(& &1.seq) |> Enum.uniq() |> length() == 20
    assert List.last(recent).path == "/3/movie/6"
  end

  test "reads on a node without the tenant are empty" do
    tables = [store_table: :no_store, recent_table: :no_recent]
    assert Traffic.recent(tables) == []
    assert Traffic.last(:tmdb, tables) == nil
    assert %{requests: 0} = Traffic.totals(:tmdb, [seconds: 900, now: @now] ++ tables)
    assert length(Traffic.series(:tmdb, :"5m", [now: @now] ++ tables).starts) == 30
  end
end
