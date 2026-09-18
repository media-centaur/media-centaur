defmodule MediaCentaur.Search.IncidentContextTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.IntegrationAvailability.Status
  alias MediaCentaur.Search.IncidentContext

  @now ~U[2026-08-01 01:00:00Z]
  @grace_seconds 180

  defp decide(status), do: IncidentContext.decide(status, @now, @grace_seconds)

  defp up, do: %Status{integration: :prowlarr, state: :up, observed_at: @now}

  defp down(reason, since),
    do: %Status{integration: :prowlarr, state: {:down, since, reason}, observed_at: @now}

  test "an available Prowlarr is :ok" do
    assert decide(up()) == :ok
  end

  test "an unreachable provider past the grace window faults" do
    assert {:fault, :search_provider_unreachable, :warning, %{headline: headline}} =
             decide(down(:unreachable, ~U[2026-08-01 00:50:00Z]))

    assert headline == "Search provider unreachable"
  end

  test "blind indexers past the grace window fault as their own condition" do
    assert {:fault, :search_indexers_unavailable, :warning, %{headline: "No indexer available"}} =
             decide(down(:blind, ~U[2026-08-01 00:50:00Z]))
  end

  test "a rejected key is its own condition, not an unreachable provider" do
    assert {:fault, :search_provider_rejected, :warning, %{headline: headline}} =
             decide(down(:rejected, ~U[2026-08-01 00:50:00Z]))

    assert headline == "Search provider rejected the API key"
  end

  test "a fault younger than the grace window stays quiet" do
    assert decide(down(:blind, ~U[2026-08-01 00:59:00Z])) == :ok
  end

  test "an outage nobody has looked at in days still faults — the probe keeps the value true" do
    assert {:fault, :search_indexers_unavailable, :warning, %{}} =
             decide(down(:blind, ~U[2026-07-29 00:00:00Z]))
  end

  test "a broken hand-off is the pursuit probe's condition, not search's" do
    assert decide(down(:client_unavailable, ~U[2026-08-01 00:50:00Z])) == :ok
  end
end
