defmodule MediaCentaur.Downloads.IncidentContextTest do
  @moduledoc """
  Pure tests for the download-client health assessor (ADR-054). The whole point
  of routing connectivity faults through `assess/0` instead of the `:log` track
  is the **grace window**: a transient blip must NOT fault. Only a sustained
  outage — measured from the `{:offline, since}` onset the producer grades —
  surfaces an incident.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Downloads.ClientStatus
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

  describe "decide/3 — the fault says which client, since when, and why" do
    defp client(upstream, url, connectivity, last_error \\ nil) do
      %ClientStatus{upstream: upstream, url: url, connectivity: connectivity, last_error: last_error}
    end

    test "an outage lists every client: the offline one with its duration and cause, the healthy one as answering" do
      offline_since = seconds_ago(2 * 3600 + 5 * 60)

      queue = %QueueState{
        connectivity: {:offline, offline_since},
        clients: %{
          torrent: client(:qbittorrent, "http://127.0.0.1:8080", {:offline, offline_since}, "HTTP 404"),
          usenet: client(:sabnzbd, "http://127.0.0.1:8085", :live)
        }
      }

      assert {:fault, :download_client_unreachable, :warning, %{detail: detail}} =
               IncidentContext.decide(queue, now(), @grace)

      assert detail ==
               "qBittorrent at http://127.0.0.1:8080 — offline for 2h 5m (HTTP 404)\n" <>
                 "SABnzbd at http://127.0.0.1:8085 — answering"
    end

    test "a credential rejection names the client that refused" do
      queue = %QueueState{
        connectivity: :auth_failed,
        clients: %{
          usenet: client(:sabnzbd, "http://127.0.0.1:8085", :auth_failed, "credentials rejected")
        }
      }

      assert {:fault, :download_client_auth_failed, :error, %{detail: detail}} =
               IncidentContext.decide(queue, now(), @grace)

      assert detail == "SABnzbd at http://127.0.0.1:8085 — credentials rejected"
    end

    test "a single missed poll inside an outage elsewhere reads as such" do
      offline_since = seconds_ago(600)

      queue = %QueueState{
        connectivity: {:offline, offline_since},
        clients: %{
          torrent: client(:qbittorrent, "http://127.0.0.1:8080", {:offline, offline_since}, "timed out"),
          usenet:
            client(:sabnzbd, "http://127.0.0.1:8085", {:transient_failure, seconds_ago(5)}, "timed out")
        }
      }

      assert {:fault, _kind, _severity, %{detail: detail}} = IncidentContext.decide(queue, now(), @grace)

      assert detail ==
               "qBittorrent at http://127.0.0.1:8080 — offline for 10m (timed out)\n" <>
                 "SABnzbd at http://127.0.0.1:8085 — missed the last poll (timed out)"
    end
  end

  describe "completed_dir_fault/1 — where finished downloads land" do
    test "a directory that exists inside a media directory → :ok" do
      assert IncidentContext.completed_dir_fault(:ok) == :ok
    end

    test "a missing directory → warning naming it" do
      assert {:fault, :completed_dir_missing, :warning, %{headline: headline}} =
               IncidentContext.completed_dir_fault({:missing, "/mnt/sample/completed"})

      assert headline == "Finished downloads directory is missing"
    end

    test "a directory outside the media directories → warning" do
      assert {:fault, :completed_dir_not_watched, :warning, %{headline: headline}} =
               IncidentContext.completed_dir_fault({:not_watched, "/mnt/sample/completed"})

      assert headline == "Finished downloads land outside the media directories"
    end
  end
end
