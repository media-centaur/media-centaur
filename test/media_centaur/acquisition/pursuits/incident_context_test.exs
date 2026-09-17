defmodule MediaCentaur.Acquisition.Pursuits.IncidentContextTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.IncidentContext

  @window 30 * 60

  defp now, do: ~U[2026-09-17 15:40:00Z]
  defp seconds_ago(seconds), do: DateTime.add(now(), -seconds, :second)

  describe "decide/4 — the last thing known about the Prowlarr → client hop" do
    test "nothing has failed → :ok" do
      assert IncidentContext.decide(nil, nil, now(), @window) == :ok
    end

    test "a recent failure and no grab since → warning" do
      assert {:fault, :download_client_handoff_failed, :warning, %{headline: headline}} =
               IncidentContext.decide(seconds_ago(60), nil, now(), @window)

      assert headline == "Prowlarr could not hand releases to the download client"
    end

    test "a recent failure with an older success still faults — the failure is the latest word" do
      assert {:fault, :download_client_handoff_failed, :warning, _ids} =
               IncidentContext.decide(seconds_ago(60), seconds_ago(600), now(), @window)
    end

    test "a grab that succeeded after the failure clears it" do
      assert IncidentContext.decide(seconds_ago(600), seconds_ago(60), now(), @window) == :ok
    end

    test "a failure older than the window has aged out" do
      assert IncidentContext.decide(seconds_ago(@window + 1), nil, now(), @window) == :ok
    end
  end

  describe "assess/0 — reads the targets the retry loop stamps" do
    test "a seeking target snoozed on download_client_unavailable faults" do
      create_pursuit_with_target(%{
        state: "seeking",
        status: "seeking",
        last_attempt_outcome: "download_client_unavailable",
        last_attempt_at: DateTime.utc_now(:second)
      })

      assert {:fault, :download_client_handoff_failed, :warning, _ids} = IncidentContext.assess()
    end

    test "a later successful grab on any pursuit clears it" do
      create_pursuit_with_target(%{
        state: "seeking",
        status: "seeking",
        last_attempt_outcome: "download_client_unavailable",
        last_attempt_at: DateTime.add(DateTime.utc_now(:second), -120, :second)
      })

      create_pursuit_with_target(%{
        state: "seeking",
        status: "acquired",
        acquired_at: DateTime.utc_now(:second)
      })

      assert IncidentContext.assess() == :ok
    end

    test "a cancelled target's old failure does not count" do
      create_pursuit_with_target(%{
        state: "cancelled",
        status: "cancelled",
        last_attempt_outcome: "download_client_unavailable",
        last_attempt_at: DateTime.utc_now(:second)
      })

      assert IncidentContext.assess() == :ok
    end

    test "nothing stamped → :ok" do
      assert IncidentContext.assess() == :ok
    end

    test "the acquisition composite surfaces it as the component's condition" do
      create_pursuit_with_target(%{
        state: "seeking",
        status: "seeking",
        last_attempt_outcome: "download_client_unavailable",
        last_attempt_at: DateTime.utc_now(:second)
      })

      assert {:fault, :download_client_handoff_failed, :warning, _ids} =
               MediaCentaur.Acquisition.IncidentContext.assess()
    end
  end
end
