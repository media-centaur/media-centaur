defmodule MediaCentaur.Social.IncidentContextTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Social.IncidentContext

  @now ~U[2026-09-02 12:00:00Z]
  @grace 180

  defp status(entries) do
    Map.new(entries, fn
      {url, state, since} -> {url, %{state: state, last_error: nil, since: since}}
      {url, state, since, error} -> {url, %{state: state, last_error: error, since: since}}
    end)
  end

  describe "detail" do
    test "lists every relay with its state, how long it has been there, and its last error" do
      old = DateTime.add(@now, -720, :second)

      assert {:fault, :relay_degraded, :warning, %{detail: detail}} =
               IncidentContext.decide(
                 status([
                   {"wss://b/", :connected, @now},
                   {"wss://a/", :disconnected, old, "connection refused"}
                 ]),
                 @now,
                 @grace
               )

      assert detail == "wss://a/ — disconnected for 12 min (connection refused)\nwss://b/ — connected"
    end

    test "an auth failure names the relay that rejected the identity" do
      assert {:fault, :relay_auth_failed, :error, %{detail: detail}} =
               IncidentContext.decide(
                 status([{"wss://a/", :auth_failed, DateTime.add(@now, -90, :second), "restricted"}]),
                 @now,
                 @grace
               )

      assert detail == "wss://a/ — rejected this identity 1 min ago (restricted)"
    end

    test "durations read in seconds, minutes or hours" do
      for {offset, expected} <- [{40, "40 s"}, {600, "10 min"}, {7_800, "2 h"}] do
        since = DateTime.add(@now, -offset, :second)

        assert {:fault, :relays_unreachable, :error, %{detail: detail}} =
                 IncidentContext.decide(status([{"wss://a/", :disconnected, since}]), @now, 30)

        assert detail == "wss://a/ — disconnected for #{expected}"
      end
    end
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
