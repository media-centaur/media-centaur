defmodule MediaCentaur.Search.IncidentContextTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Search.IncidentContext
  alias MediaCentaur.Search.IndexerHealth

  @now ~U[2026-08-01 01:00:00Z]
  @grace_seconds 180
  @staleness_seconds 900

  defp decide(health), do: IncidentContext.decide(health, @now, @grace_seconds, @staleness_seconds)

  defp health(state, opts \\ []) do
    %IndexerHealth{
      state: state,
      checked_at: Keyword.get(opts, :checked_at, @now),
      since: Keyword.get(opts, :since)
    }
  end

  test "no observation yet is :ok" do
    assert decide(nil) == :ok
  end

  test "healthy, unconfigured, and degraded states never fault" do
    assert decide(health(:ok)) == :ok
    assert decide(health(:unconfigured)) == :ok
    assert decide(health(:degraded, since: ~U[2026-08-01 00:00:00Z])) == :ok
  end

  test "a blind roster older than the grace window faults" do
    assert {:fault, :search_indexers_unavailable, :warning, %{}} =
             decide(health(:blind, since: ~U[2026-08-01 00:50:00Z]))
  end

  test "an unreachable provider older than the grace window faults" do
    assert {:fault, :search_provider_unreachable, :warning, %{}} =
             decide(health(:unreachable, since: ~U[2026-08-01 00:50:00Z]))
  end

  test "a fault younger than the grace window stays quiet" do
    assert decide(health(:blind, since: ~U[2026-08-01 00:59:00Z])) == :ok
  end

  test "a stale observation never faults — nothing is exercising search" do
    assert decide(
             health(:blind,
               since: ~U[2026-08-01 00:00:00Z],
               checked_at: ~U[2026-08-01 00:40:00Z]
             )
           ) == :ok
  end
end
