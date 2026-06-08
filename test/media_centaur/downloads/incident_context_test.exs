defmodule MediaCentaur.Downloads.IncidentContextTest do
  @moduledoc """
  Pure tests for the download-client health assessor (ADR-054). The whole point
  of routing connectivity faults through `assess/0` instead of the `:log` track
  is the **grace window**: a single failed poll while the client was recently
  healthy is a transient blip and must NOT fault. Only sustained unreachability
  surfaces an incident.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Downloads.IncidentContext
  alias MediaCentaur.Downloads.QueueState

  @grace 180

  # A fixed "now"; fixtures express health relative to it.
  defp now, do: ~U[2026-06-08 12:00:00Z]
  defp seconds_ago(n), do: DateTime.add(now(), -n, :second)

  describe "decide/3 — healthy states never fault" do
    test "no error → :ok" do
      state = %QueueState{last_error: nil, last_successful_poll_at: seconds_ago(30)}
      assert IncidentContext.decide(state, now(), @grace) == :ok
    end

    test "not configured → :ok (no client is not a fault)" do
      state = %QueueState{last_error: :not_configured}
      assert IncidentContext.decide(state, now(), @grace) == :ok
    end
  end

  describe "decide/3 — transient connectivity is absorbed by the grace window" do
    test "unreachable but a poll succeeded within the grace window → :ok (the blip)" do
      state = %QueueState{last_error: :unreachable, last_successful_poll_at: seconds_ago(60)}
      assert IncidentContext.decide(state, now(), @grace) == :ok
    end

    test "offline since inside the grace window → :ok" do
      state = %QueueState{last_error: {:offline, seconds_ago(60)}}
      assert IncidentContext.decide(state, now(), @grace) == :ok
    end
  end

  describe "decide/3 — sustained connectivity loss faults" do
    test "unreachable with last success older than grace → unreachable warning" do
      state = %QueueState{last_error: :unreachable, last_successful_poll_at: seconds_ago(300)}

      assert {:fault, :download_client_unreachable, :warning, _ids} =
               IncidentContext.decide(state, now(), @grace)
    end

    test "unreachable and never succeeded → unreachable warning" do
      state = %QueueState{last_error: :unreachable, last_successful_poll_at: nil}

      assert {:fault, :download_client_unreachable, :warning, _ids} =
               IncidentContext.decide(state, now(), @grace)
    end

    test "offline since older than grace → unreachable warning" do
      state = %QueueState{last_error: {:offline, seconds_ago(300)}}

      assert {:fault, :download_client_unreachable, :warning, _ids} =
               IncidentContext.decide(state, now(), @grace)
    end
  end

  describe "decide/3 — auth failure is an immediate error (not transient)" do
    test "auth_failed faults at :error regardless of grace" do
      state = %QueueState{last_error: :auth_failed, last_successful_poll_at: seconds_ago(5)}

      assert {:fault, :download_client_auth_failed, :error, _ids} =
               IncidentContext.decide(state, now(), @grace)
    end
  end
end
