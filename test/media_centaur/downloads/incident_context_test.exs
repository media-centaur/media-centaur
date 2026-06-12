defmodule MediaCentaur.Downloads.IncidentContextTest do
  @moduledoc """
  Pure tests for the download-client health assessor (ADR-054). The whole point
  of routing connectivity faults through `assess/0` instead of the `:log` track
  is the **grace window**: a transient blip must NOT fault. Only a sustained
  outage — measured from the `{:offline, since}` onset the producer grades —
  surfaces an incident.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Downloads.IncidentContext
  alias MediaCentaur.Downloads.QueueState

  @grace 180

  # A fixed "now"; fixtures express health relative to it.
  defp now, do: ~U[2026-06-08 12:00:00Z]
  defp seconds_ago(n), do: DateTime.add(now(), -n, :second)

  defp state(connectivity), do: %QueueState{connectivity: connectivity}

  describe "decide/3 — healthy states never fault" do
    test "live → :ok" do
      assert IncidentContext.decide(state(:live), now(), @grace) == :ok
    end

    test "initializing → :ok (startup is not an outage)" do
      assert IncidentContext.decide(state(:initializing), now(), @grace) == :ok
    end

    test "not configured → :ok (no client is not a fault)" do
      assert IncidentContext.decide(state(:not_configured), now(), @grace) == :ok
    end
  end

  describe "decide/3 — transient connectivity is absorbed" do
    test "a single failed poll (transient blip) → :ok regardless of age" do
      assert IncidentContext.decide(state({:transient_failure, seconds_ago(60)}), now(), @grace) ==
               :ok

      assert IncidentContext.decide(state({:transient_failure, seconds_ago(600)}), now(), @grace) ==
               :ok
    end

    test "offline with onset inside the grace window → :ok" do
      assert IncidentContext.decide(state({:offline, seconds_ago(60)}), now(), @grace) == :ok
    end
  end

  describe "decide/3 — sustained connectivity loss faults" do
    test "offline with onset older than grace → unreachable warning" do
      assert {:fault, :download_client_unreachable, :warning, _ids} =
               IncidentContext.decide(state({:offline, seconds_ago(300)}), now(), @grace)
    end

    test "offline exactly at the grace boundary faults" do
      assert {:fault, :download_client_unreachable, :warning, _ids} =
               IncidentContext.decide(state({:offline, seconds_ago(@grace)}), now(), @grace)
    end
  end

  describe "decide/3 — auth failure is an immediate error (not transient)" do
    test "auth_failed faults at :error regardless of grace" do
      assert {:fault, :download_client_auth_failed, :error, _ids} =
               IncidentContext.decide(state(:auth_failed), now(), @grace)
    end
  end
end
