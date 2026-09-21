defmodule MediaCentaur.Showcase.SyntheticTrafficTest do
  use MediaCentaur.Case, async: false

  alias MediaCentaur.HttpClient.{Instrument, Traffic, Upstream}
  alias MediaCentaur.Showcase.Stubs
  alias MediaCentaur.Showcase.SyntheticTraffic
  alias MediaCentaur.TimeSeries.{Store, Window}

  @now 1_789_000_000

  setup do
    table = :"synthetic_traffic_#{System.unique_integer([:positive])}"

    start_supervised!({Store, name: :"#{table}_store", table: table, schema: Traffic.schema()})

    %{table: table}
  end

  describe "backfill/3" do
    test "every window the Connections panel offers has bars to draw", %{table: table} do
      :ok = SyntheticTraffic.backfill(table, [:qbittorrent], @now)

      for window <- Window.all() do
        series = Traffic.series(:qbittorrent, window, store_table: table, now: @now)
        drawn = Enum.sum(series.went_out) + Enum.sum(series.failed) + Enum.sum(series.cached)

        assert drawn > 0, "the #{inspect(window)} window would render an empty strip"
      end
    end

    test "each upstream gets its own history", %{table: table} do
      upstreams = [:tmdb, :prowlarr, :qbittorrent]
      :ok = SyntheticTraffic.backfill(table, upstreams, @now)

      totals =
        Map.new(upstreams, fn upstream ->
          {upstream, Traffic.totals(upstream, store_table: table, now: @now, seconds: 31 * 86_400)}
        end)

      for {upstream, total} <- totals do
        assert total.requests > 0, "#{upstream} would show no traffic at all"
      end

      assert totals[:qbittorrent].requests > totals[:prowlarr].requests
    end

    test "the demo's store is never asked to restore a history", %{table: table} do
      # The showcase store is started without a snapshot path, so the
      # table is empty at boot and this backfill is the only writer. If
      # that ever changed, a restart would stack a second month on the
      # first, so pin the assumption rather than leaving it implicit.
      :ok = SyntheticTraffic.backfill(table, [:tmdb], @now)
      once = Traffic.totals(:tmdb, store_table: table, now: @now, seconds: 3_600)

      :ok = SyntheticTraffic.backfill(table, [:tmdb], @now)
      twice = Traffic.totals(:tmdb, store_table: table, now: @now, seconds: 3_600)

      assert once.requests > 0

      assert twice.requests == once.requests * 2,
             "counters accumulate — the showcase relies on starting from an empty table"
    end

    test "the cache answers some reads and never carries latency", %{table: table} do
      :ok = SyntheticTraffic.backfill(table, [:tmdb], @now)

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

  describe "which upstreams are fabricated" do
    test "the stubbed upstreams are backfilled but not generated live" do
      # Showcase.Stubs answers Prowlarr and the download client from
      # fixtures, but through the real HTTP client — the queue monitor's
      # poll is a genuine recorded request. Fabricating alongside it would
      # count one poll twice. The past is still fabricated: nothing was
      # observed before this boot.
      for upstream <- Stubs.upstreams() do
        refute upstream in SyntheticTraffic.live_upstreams(),
               "#{upstream} talks for real; generating its present double-counts"
      end
    end

    test "live upstreams are the instance's upstreams minus the stubbed ones" do
      assert SyntheticTraffic.live_upstreams() ==
               Enum.reject(SyntheticTraffic.upstreams(), &(&1 in Stubs.upstreams()))
    end

    test "every strip the panel can row has a generator behind it" do
      # The generator is a deliberate superset of the panel: whichever
      # integrations turn out to be configured, no rendered strip can be
      # left without history. Filtering by configured-ness here instead
      # would read the Settings database before it has been overlaid.
      every_possible_strip =
        Upstream.active_ids(%{
          prowlarr: true,
          download_client: true,
          usenet_download_client: true
        })

      for upstream <- every_possible_strip do
        assert upstream in SyntheticTraffic.upstreams(),
               "#{upstream} can be rowed by the panel but is never fabricated"
      end
    end
  end
end
