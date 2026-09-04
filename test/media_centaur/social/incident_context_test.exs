defmodule MediaCentaur.Social.IncidentContextTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Social.IncidentContext

  @now ~U[2026-09-02 12:00:00Z]
  @grace 180

  defp status(entries) do
    Map.new(entries, fn {url, state, since} ->
      {url, %{state: state, last_error: nil, since: since}}
    end)
  end

  test "no relays is healthy" do
    assert IncidentContext.decide(%{}, @now, @grace) == :ok
  end

  test "all connected is healthy" do
    assert IncidentContext.decide(status([{"wss://a/", :connected, @now}]), @now, @grace) == :ok
  end

  test "auth failure faults immediately" do
    assert {:fault, :relay_auth_failed, :error, %{headline: "Relay rejected this identity"}} =
             IncidentContext.decide(status([{"wss://a/", :auth_failed, @now}]), @now, @grace)
  end

  test "a synced relay is healthy" do
    assert IncidentContext.decide(status([{"wss://a/", :synced, @now}]), @now, @grace) == :ok
  end

  test "disconnected inside the grace window is still healthy" do
    since = DateTime.add(@now, -60, :second)
    assert IncidentContext.decide(status([{"wss://a/", :disconnected, since}]), @now, @grace) == :ok
  end

  test "all relays down past grace is an error; some down is a warning" do
    old = DateTime.add(@now, -600, :second)

    assert {:fault, :relays_unreachable, :error, _} =
             IncidentContext.decide(status([{"wss://a/", :disconnected, old}]), @now, @grace)

    assert {:fault, :relay_degraded, :warning, _} =
             IncidentContext.decide(
               status([{"wss://a/", :disconnected, old}, {"wss://b/", :connected, @now}]),
               @now,
               @grace
             )
  end

  test "a relay still connecting is not yet a fault, however long it has taken" do
    old = DateTime.add(@now, -600, :second)
    assert IncidentContext.decide(status([{"wss://a/", :connecting, old}]), @now, @grace) == :ok
  end

  test "an auth failure outranks a plain outage" do
    old = DateTime.add(@now, -600, :second)

    assert {:fault, :relay_auth_failed, :error, _} =
             IncidentContext.decide(
               status([{"wss://a/", :disconnected, old}, {"wss://b/", :auth_failed, @now}]),
               @now,
               @grace
             )
  end
end
