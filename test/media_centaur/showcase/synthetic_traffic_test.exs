defmodule MediaCentaur.Showcase.SyntheticTrafficTest do
  use MediaCentaur.Case, async: false

  alias MediaCentaur.HttpClient.{Instrument, Traffic}
  alias MediaCentaur.Showcase.SyntheticTraffic
  alias MediaCentaur.TimeSeries.{Store, Window}

  @now 1_789_000_000

  setup do
    table = :"synthetic_traffic_#{System.unique_integer([:positive])}"
    server = :"#{table}_store"

    start_supervised!({Store, name: server, table: table, schema: Traffic.schema()})

    %{table: table, server: server}
  end

  describe "backfill/4" do
    test "every window the Connections panel offers has bars to draw", %{table: table, server: server} do
      :ok = SyntheticTraffic.backfill(server, table, [:qbittorrent], @now)

      for window <- Window.all() do
        series = Traffic.series(:qbittorrent, window, store_table: table, now: @now)
        drawn = Enum.sum(series.went_out) + Enum.sum(series.failed) + Enum.sum(series.cached)

        assert drawn > 0, "the #{inspect(window)} window would render an empty strip"
      end
    end

    test "each upstream gets its own history", %{table: table, server: server} do
      upstreams = [:tmdb, :prowlarr, :qbittorrent]
      :ok = SyntheticTraffic.backfill(server, table, upstreams, @now)

      totals =
        Map.new(upstreams, fn upstream ->
          {upstream, Traffic.totals(upstream, store_table: table, now: @now, seconds: 31 * 86_400)}
        end)

      for {upstream, total} <- totals do
        assert total.requests > 0, "#{upstream} would show no traffic at all"
      end

      assert totals[:qbittorrent].requests > totals[:prowlarr].requests
    end

    test "backfilling again replaces the history rather than stacking on it", %{
      table: table,
      server: server
    } do
      # The store restores its snapshot at boot and the process backfills
      # straight after, so without the clear a restarted demo instance
      # would report twice the requests it did the day before.
      :ok = SyntheticTraffic.backfill(server, table, [:tmdb], @now)
      once = Traffic.totals(:tmdb, store_table: table, now: @now, seconds: 3_600)

      :ok = SyntheticTraffic.backfill(server, table, [:tmdb], @now)
      twice = Traffic.totals(:tmdb, store_table: table, now: @now, seconds: 3_600)

      assert twice.requests == once.requests
      assert once.requests > 0
    end

    test "the cache answers some reads and never carries latency", %{table: table, server: server} do
      :ok = SyntheticTraffic.backfill(server, table, [:tmdb], @now)

      series = Traffic.series(:tmdb, :"1w", store_table: table, now: @now)

      assert Enum.sum(series.cached) > 0
      assert Enum.all?(series.went_out, &(&1 >= 0)), "cache hits must not go negative"
    end
  end

  describe "emit_tick/2" do
    setup do
      handler = "synthetic-traffic-test-#{System.unique_integer([:positive])}"
      test = self()

      :telemetry.attach(
        handler,
        Instrument.stop_event(),
        fn _event, measurements, metadata, _config ->
          send(test, {:http_request, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      :ok
    end

    test "emits ordinary HTTP stop events, so Traffic records them the usual way" do
      :ok = SyntheticTraffic.emit_tick([:qbittorrent], @now)

      assert_received {:http_request, %{duration: duration}, metadata}
      assert metadata.upstream == :qbittorrent
      assert metadata.method == :get
      assert metadata.cache in [:hit, :miss]
      assert is_integer(metadata.status)
      assert duration >= 0
    end

    test "a cache hit reports no time spent on the wire" do
      :ok = SyntheticTraffic.emit_tick([:tmdb, :tmdb_images, :prowlarr, :qbittorrent], @now + 7)

      events = drain()

      for {measurements, metadata} <- events, metadata.cache == :hit do
        assert measurements.duration == 0
        assert metadata.status == 200
      end

      assert events != []
    end

    defp drain(acc \\ []) do
      receive do
        {:http_request, measurements, metadata} -> drain([{measurements, metadata} | acc])
      after
        0 -> acc
      end
    end
  end
end
