defmodule MediaCentaur.Search.ProbeJobTest do
  # Sync: probing writes `:persistent_term` through `IntegrationAvailability`.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.ProbeJob

  @roster_ok [%{"id" => 1, "name" => "Sample Indexer", "enable" => true, "protocol" => "usenet"}]

  @usenet_client %{
    "id" => 2,
    "name" => "Sample Usenet Client",
    "implementation" => "Sabnzbd",
    "enable" => true,
    "protocol" => "usenet",
    "fields" => []
  }

  defp stub_handoff(valid?) do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/downloadclient"} ->
          Req.Test.json(conn, [@usenet_client])

        {"POST", "/api/v1/downloadclient/testall"} ->
          Req.Test.json(conn, [%{"id" => 2, "isValid" => valid?, "validationFailures" => []}])
      end
    end)
  end

  describe "perform/1 for prowlarr" do
    test "snoozes at the cadence while Prowlarr stays unreachable" do
      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:snooze, 60} = ProbeJob.perform(%Oban.Job{args: %{"integration" => "prowlarr"}})
      refute IntegrationAvailability.up?(:prowlarr)
    end

    test "completes once the roster answers" do
      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/indexer" -> Req.Test.json(conn, @roster_ok)
          "/api/v1/indexerstatus" -> Req.Test.json(conn, [])
        end
      end)

      assert :ok = ProbeJob.perform(%Oban.Job{args: %{"integration" => "prowlarr"}})
      assert IntegrationAvailability.up?(:prowlarr)
    end
  end

  describe "perform/1 for the hand-off" do
    test "snoozes while any hand-off is down, completes when both are up" do
      {:changed, _state} =
        IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})

      stub_handoff(false)

      assert {:snooze, 60} = ProbeJob.perform(%Oban.Job{args: %{"integration" => "handoff"}})
      refute IntegrationAvailability.up?({:handoff, :usenet})

      stub_handoff(true)

      assert :ok = ProbeJob.perform(%Oban.Job{args: %{"integration" => "handoff"}})
      assert IntegrationAvailability.up?({:handoff, :usenet})
    end
  end

  describe "snooze_for/2" do
    test "waits for Prowlarr's own retry time when it is later than the cadence, capped at an hour" do
      now = ~U[2026-09-17 20:00:00Z]

      assert ProbeJob.snooze_for(nil, now) == 60
      assert ProbeJob.snooze_for(~U[2026-09-17 20:00:30Z], now) == 60
      assert ProbeJob.snooze_for(~U[2026-09-17 20:10:00Z], now) == 600
      assert ProbeJob.snooze_for(~U[2026-09-18 20:00:00Z], now) == 3600
    end
  end
end
