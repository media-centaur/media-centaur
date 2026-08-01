defmodule MediaCentaur.Search.IndexerHealthTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Search.IndexerHealth
  alias MediaCentaur.Search.Prowlarr

  @now ~U[2026-08-01 00:00:00Z]

  defp indexer(id, name, enabled), do: %{id: id, name: name, enabled: enabled}
  defp backoff(id, until), do: %{indexer_id: id, disabled_till: until}

  describe "classify/3" do
    test "all enabled indexers live is :ok" do
      health =
        IndexerHealth.classify(
          [indexer(1, "Indexer A", true), indexer(2, "Indexer B", false)],
          [],
          @now
        )

      assert health.state == :ok
      assert health.enabled_count == 1
      assert health.backed_off == []
      assert health.retry_at == nil
      assert health.checked_at == @now
    end

    test "no enabled indexers is :unconfigured" do
      health = IndexerHealth.classify([indexer(1, "Indexer A", false)], [], @now)

      assert health.state == :unconfigured
      assert health.enabled_count == 0
    end

    test "every enabled indexer backed off is :blind with the soonest retry" do
      later = ~U[2026-08-01 00:30:00Z]
      sooner = ~U[2026-08-01 00:05:00Z]

      health =
        IndexerHealth.classify(
          [indexer(1, "Indexer A", true), indexer(2, "Indexer B", true)],
          [backoff(1, later), backoff(2, sooner)],
          @now
        )

      assert health.state == :blind
      assert health.retry_at == sooner

      assert health.backed_off == [
               %{name: "Indexer A", retry_at: later},
               %{name: "Indexer B", retry_at: sooner}
             ]
    end

    test "some enabled indexers backed off is :degraded" do
      until = ~U[2026-08-01 00:05:00Z]

      health =
        IndexerHealth.classify(
          [indexer(1, "Indexer A", true), indexer(2, "Indexer B", true)],
          [backoff(1, until)],
          @now
        )

      assert health.state == :degraded
      assert health.backed_off == [%{name: "Indexer A", retry_at: until}]
      assert health.retry_at == until
    end

    test "an expired back-off no longer counts" do
      expired = ~U[2026-07-31 23:00:00Z]

      health =
        IndexerHealth.classify([indexer(1, "Indexer A", true)], [backoff(1, expired)], @now)

      assert health.state == :ok
    end

    test "a back-off for a disabled indexer is ignored" do
      until = ~U[2026-08-01 00:30:00Z]

      health =
        IndexerHealth.classify(
          [indexer(1, "Indexer A", true), indexer(2, "Indexer B", false)],
          [backoff(2, until)],
          @now
        )

      assert health.state == :ok
    end
  end

  describe "unreachable/2" do
    test "wraps the transport error" do
      health = IndexerHealth.unreachable(%Req.TransportError{reason: :timeout}, @now)

      assert health.state == :unreachable
      assert health.checked_at == @now
    end
  end

  describe "problem?/1" do
    test "only degraded, blind, and unreachable are problems" do
      assert IndexerHealth.problem?(%IndexerHealth{state: :degraded, checked_at: @now})
      assert IndexerHealth.problem?(%IndexerHealth{state: :blind, checked_at: @now})
      assert IndexerHealth.problem?(%IndexerHealth{state: :unreachable, checked_at: @now})
      refute IndexerHealth.problem?(%IndexerHealth{state: :ok, checked_at: @now})
      refute IndexerHealth.problem?(%IndexerHealth{state: :unconfigured, checked_at: @now})
      refute IndexerHealth.problem?(nil)
    end
  end

  describe "blind?/1" do
    test "blind and unreachable mean the search saw nothing" do
      assert IndexerHealth.blind?(%IndexerHealth{state: :blind, checked_at: @now})
      assert IndexerHealth.blind?(%IndexerHealth{state: :unreachable, checked_at: @now})
      refute IndexerHealth.blind?(%IndexerHealth{state: :degraded, checked_at: @now})
      refute IndexerHealth.blind?(%IndexerHealth{state: :ok, checked_at: @now})
      refute IndexerHealth.blind?(nil)
    end
  end

  describe "cache" do
    setup do
      IndexerHealth.clear_cache()
      on_exit(fn -> IndexerHealth.clear_cache() end)
      :ok
    end

    test "cached/0 is nil before any observation" do
      assert IndexerHealth.cached() == nil
    end

    test "cache_put/1 stamps the fault onset on the first faulty observation" do
      health = IndexerHealth.cache_put(%IndexerHealth{state: :blind, checked_at: @now})

      assert health.since == @now
      assert IndexerHealth.cached() == health
    end

    test "consecutive faulty observations keep the original onset" do
      IndexerHealth.cache_put(%IndexerHealth{state: :unreachable, checked_at: @now})

      later = ~U[2026-08-01 00:10:00Z]
      health = IndexerHealth.cache_put(%IndexerHealth{state: :blind, checked_at: later})

      assert health.since == @now
    end

    test "a healthy observation resets the onset" do
      IndexerHealth.cache_put(%IndexerHealth{state: :blind, checked_at: @now})
      IndexerHealth.cache_put(%IndexerHealth{state: :ok, checked_at: ~U[2026-08-01 00:05:00Z]})

      later = ~U[2026-08-01 00:10:00Z]
      health = IndexerHealth.cache_put(%IndexerHealth{state: :blind, checked_at: later})

      assert health.since == later
    end
  end

  describe "check/1" do
    setup do
      IndexerHealth.clear_cache()
      on_exit(fn -> IndexerHealth.clear_cache() end)

      Req.Test.stub(:prowlarr_health, fn conn ->
        case conn.request_path do
          "/api/v1/indexer" ->
            Req.Test.json(conn, [
              %{"id" => 1, "name" => "Indexer A", "enable" => true}
            ])

          "/api/v1/indexerstatus" ->
            Req.Test.json(conn, [
              %{"indexerId" => 1, "disabledTill" => "2099-01-01T00:00:00Z"}
            ])
        end
      end)

      client =
        Req.new(plug: {Req.Test, :prowlarr_health}, retry: false, base_url: "http://prowlarr.test")

      {:ok, client: client}
    end

    test "fetches, classifies, and caches", %{client: client} do
      health = IndexerHealth.check(client)

      assert health.state == :blind
      assert [%{name: "Indexer A"}] = health.backed_off
      assert IndexerHealth.cached() == health
    end

    test "a transport error caches :unreachable" do
      Req.Test.stub(:prowlarr_health, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      client =
        Req.new(
          plug: {Req.Test, :prowlarr_health},
          retry: false,
          base_url: "http://prowlarr.test"
        )

      health = IndexerHealth.check(client)

      assert health.state == :unreachable
      assert IndexerHealth.cached().state == :unreachable
    end
  end

  describe "Prowlarr.indexer_snapshot/1" do
    test "parses indexers and back-offs" do
      Req.Test.stub(:prowlarr_snapshot, fn conn ->
        case conn.request_path do
          "/api/v1/indexer" ->
            Req.Test.json(conn, [
              %{"id" => 15, "name" => "Indexer A", "enable" => true},
              %{"id" => 9, "name" => "Indexer B", "enable" => false}
            ])

          "/api/v1/indexerstatus" ->
            Req.Test.json(conn, [
              %{"indexerId" => 15, "disabledTill" => "2026-08-01T00:30:00Z"},
              %{"indexerId" => 9, "disabledTill" => nil}
            ])
        end
      end)

      client =
        Req.new(
          plug: {Req.Test, :prowlarr_snapshot},
          retry: false,
          base_url: "http://prowlarr.test"
        )

      assert {:ok, snapshot} = Prowlarr.indexer_snapshot(client)

      assert snapshot.indexers == [
               %{id: 15, name: "Indexer A", enabled: true},
               %{id: 9, name: "Indexer B", enabled: false}
             ]

      assert snapshot.backoffs == [
               %{indexer_id: 15, disabled_till: ~U[2026-08-01 00:30:00Z]},
               %{indexer_id: 9, disabled_till: nil}
             ]
    end

    test "propagates HTTP errors" do
      Req.Test.stub(:prowlarr_snapshot, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"error" => "Unauthorized"})
      end)

      client =
        Req.new(
          plug: {Req.Test, :prowlarr_snapshot},
          retry: false,
          base_url: "http://prowlarr.test"
        )

      assert {:error, {:http_error, 401, _body}} = Prowlarr.indexer_snapshot(client)
    end
  end
end
