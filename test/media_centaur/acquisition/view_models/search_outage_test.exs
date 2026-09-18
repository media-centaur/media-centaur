defmodule MediaCentaur.Acquisition.ViewModels.SearchOutageTest do
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Acquisition.ViewModels.SearchOutage
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  @t0 ~U[2026-09-18 10:00:00Z]

  defp down(reason), do: %Status{integration: :prowlarr, state: {:down, @t0, reason}, observed_at: @t0}

  describe "reason/1" do
    test "an up Prowlarr has no outage sentence" do
      assert SearchOutage.reason(%Status{integration: :prowlarr, state: :up}) == nil
    end

    test "each down reason reads mid-sentence" do
      assert SearchOutage.reason(down(:unreachable)) == "Prowlarr is unreachable"
      assert SearchOutage.reason(down(:rejected)) == "Prowlarr rejected your API key"
      assert SearchOutage.reason(down(:blind)) == "no indexers are answering"
    end

    test "a broken hand-off is not a search outage — the pursuit says that in its own words" do
      assert SearchOutage.reason(down(:client_unavailable)) == nil
    end
  end

  describe "reason/0" do
    test "reads the published Prowlarr availability" do
      assert SearchOutage.reason() == nil

      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :rejected})

      assert SearchOutage.reason() == "Prowlarr rejected your API key"
    end
  end
end
