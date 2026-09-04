defmodule MediaCentaur.Social.IncidentContext do
  @moduledoc """
  The friend network's relay-health probe — the `assess/0` the
  `ErrorReports.Evaluator` polls to own a single `:subsystem` incident for
  the `social` component (ADR-054).

  Relay connectivity is a *health condition*, not a stream of log lines:
  a relay drops and reconnects on its own backoff all day, and every drop
  already logs under `:nostr`. Expressed as an `assess/0` it gets the
  three properties the `:log` track lacks — one incident per
  `{component, kind}` however many connections misbehave, a grace window
  so a reconnect that takes seconds never surfaces, and auto-resolution
  when the evaluator next sees `:ok`.

  ## Fault conditions

    * `:relay_auth_failed` (**error**) — a relay rejected this identity
      (NIP-42 auth). Not transient and not something waiting fixes;
      surfaces immediately, no grace.
    * `:relays_unreachable` (**error**) — every configured relay has been
      disconnected for longer than the grace window. Nothing can be sent
      or received.
    * `:relay_degraded` (**warning**) — some, but not all, relays are in
      that state. Recommendations still flow through the rest.

  No relays configured is never a fault: an install that has not set up
  the friend network is not broken. Neither is a relay still working
  through its first connect (`:connecting`) — it has not failed yet.

  The decision is the pure `decide/3` over `Social.Connections.status/0`
  (whose entries carry `since`, the onset of their current state);
  `assess/0` is the thin shell that reads the status map and the current
  time, then defers to it.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.Social.Connections

  # How long a relay must have been disconnected before it counts toward a
  # fault — long enough that the connection's own reconnect backoff wins
  # first, short enough that a real outage shows up promptly. Same window
  # the download-client and search probes use.
  @grace_seconds 180

  @type fault :: {:fault, atom(), :warning | :error, map()}

  @doc "Health probe polled by the diagnostics evaluator. Side-effect-free."
  @spec assess() :: :ok | fault()
  @impl true
  def assess, do: decide(Connections.status(), DateTime.utc_now(), @grace_seconds)

  @doc """
  Pure fault decision over the relay status map.

    * `status` — `Social.Connections.status/0`.
    * `now` — current time.
    * `grace_seconds` — how long a relay must have been disconnected,
      measured from `since`, before it counts as down.

  An auth failure outranks an outage: it is the one condition no amount
  of waiting fixes.
  """
  @spec decide(%{optional(String.t()) => Connections.entry()}, DateTime.t(), pos_integer()) ::
          :ok | fault()
  def decide(status, now, grace_seconds) do
    entries = Map.values(status)
    down = Enum.filter(entries, &down?(&1, now, grace_seconds))

    cond do
      entries == [] ->
        :ok

      Enum.any?(entries, &(&1.state == :auth_failed)) ->
        {:fault, :relay_auth_failed, :error, %{headline: "Relay rejected this identity"}}

      down == [] ->
        :ok

      length(down) == length(entries) ->
        {:fault, :relays_unreachable, :error, %{headline: "No relay reachable"}}

      true ->
        {:fault, :relay_degraded, :warning, %{headline: "A relay is unreachable"}}
    end
  end

  defp down?(%{state: :disconnected, since: %DateTime{} = since}, now, grace_seconds),
    do: DateTime.diff(now, since, :second) >= grace_seconds

  defp down?(_entry, _now, _grace_seconds), do: false
end
