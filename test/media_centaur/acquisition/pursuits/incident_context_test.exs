defmodule MediaCentaur.Acquisition.Pursuits.IncidentContextTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Pursuits.IncidentContext
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  @t0 ~U[2026-09-17 20:00:00Z]
  @grace 180

  defp down(slot, since) do
    %Status{
      integration: {:handoff, slot},
      state: {:down, since, :client_unavailable},
      observed_at: since
    }
  end

  defp up(slot), do: %Status{integration: {:handoff, slot}, state: :up, observed_at: @t0}

  describe "decide/3" do
    test "both hand-offs up is ok" do
      assert IncidentContext.decide([up(:usenet), up(:torrent)], @t0, @grace) == :ok
    end

    test "a hand-off down inside the grace window is not yet a fault" do
      now = DateTime.add(@t0, 60, :second)

      assert IncidentContext.decide([down(:usenet, @t0), up(:torrent)], now, @grace) == :ok
    end

    test "a hand-off down past the grace window is a warning" do
      now = DateTime.add(@t0, @grace + 1, :second)

      assert {:fault, :download_client_handoff_failed, :warning,
              %{headline: "Prowlarr could not hand releases to the download client"}} =
               IncidentContext.decide([up(:usenet), down(:torrent, @t0)], now, @grace)
    end
  end

  describe "assess/0 — reads the live hand-off availability" do
    test "nothing observed yet is ok" do
      assert IncidentContext.assess() == :ok
    end

    test "a hand-off down past the grace window faults" do
      report_handoff_down(:usenet, @grace + 60)

      assert {:fault, :download_client_handoff_failed, :warning, _ids} = IncidentContext.assess()
    end

    test "a hand-off that has only just gone down does not fault yet" do
      report_handoff_down(:usenet, 10)

      assert IncidentContext.assess() == :ok
    end

    test "the acquisition composite surfaces it as the component's condition" do
      report_handoff_down(:torrent, @grace + 60)

      assert {:fault, :download_client_handoff_failed, :warning, _ids} =
               MediaCentaur.Acquisition.IncidentContext.assess()
    end
  end

  defp report_handoff_down(slot, seconds_ago) do
    IntegrationAvailability.report({:handoff, slot}, {:down, :client_unavailable},
      now: DateTime.add(DateTime.utc_now(), -seconds_ago, :second)
    )
  end
end
