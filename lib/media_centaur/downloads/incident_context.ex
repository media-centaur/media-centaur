defmodule MediaCentaur.Downloads.IncidentContext do
  @moduledoc """
  The acquisition subsystem's download-client health probe — the `assess/0` the
  `ErrorReports.Evaluator` polls to own a single `:subsystem` incident for
  download-client connectivity (ADR-054).

  ## Why this exists

  Download-client connectivity failures (qBittorrent timeouts, unreachable host)
  used to land on the `:log` incident track: every `Log.warning` minted a
  durable, board-visible incident with no grouping across call layers, no
  threshold, and no auto-resolution. One momentary stall produced 2–3 duplicate,
  never-closing incidents (one per code path that logged it).

  Connectivity is a *health condition*, not a stream of log lines. Expressed as
  an `assess/0` it gets, for free, the three properties the `:log` track lacks:

    * **Grouping** — one incident per `{component, kind}`, no matter how many
      paths touch the client.
    * **Threshold** — a single failed poll while the client was recently healthy
      is absorbed by the grace window (`@unreachable_grace_seconds`); only
      sustained loss faults.
    * **Lifecycle** — the evaluator auto-resolves the incident when `assess/0`
      reports `:ok` again on recovery.

  ## Fault conditions

    * `:download_client_auth_failed` (**error**) — credentials rejected. Not
      transient; surfaces immediately (no grace).
    * `:download_client_unreachable` (**warning**) — the client is unreachable
      *and* no poll has succeeded within the grace window. A blip between two
      healthy polls is not a fault.

  `:not_configured` (no client set up) is never a fault.

  The decision is the pure `decide/3`; `assess/0` is the thin shell that reads
  `QueueMonitor`'s public `QueueState` (cached in `:persistent_term`, no
  GenServer call) and the current time, then defers to it.

  Like `SelfUpdate.IncidentContext`, this fulfils the `IncidentContext` `assess/0`
  contract **structurally rather than via `@behaviour`**: the registry binds
  assessors by `function_exported?(module, :assess, 0)` purely by name, so a
  subsystem reports health without a compile-time `Downloads → ErrorReports`
  edge. Registered under the `:acquisition` component in
  `config :media_centaur, :diagnostics_contributors`.
  """

  alias MediaCentaur.Downloads.QueueMonitor
  alias MediaCentaur.Downloads.QueueState

  # A couple of poll cycles of unreachability before a connectivity warning
  # opens — long enough that a single timed-out poll between healthy polls never
  # surfaces, short enough that a real outage shows up promptly.
  @unreachable_grace_seconds 180

  @type fault :: {:fault, atom(), :warning | :error, map()}

  @doc "Health probe polled by the diagnostics evaluator. Side-effect-free."
  @spec assess() :: :ok | fault()
  def assess do
    decide(QueueMonitor.state(), DateTime.utc_now(), @unreachable_grace_seconds)
  end

  @doc """
  Pure fault decision over the download-client queue health.

    * `state` — the latest `%QueueState{}` (`QueueMonitor.state/0`).
    * `now` — current time.
    * `grace_seconds` — how long the client may be unreachable, measured from the
      last successful poll, before a `:download_client_unreachable` warning opens.

  Auth failures ignore the grace window; a missing/healthy client never faults.
  """
  @spec decide(QueueState.t(), DateTime.t(), pos_integer()) :: :ok | fault()
  def decide(%QueueState{last_error: nil}, _now, _grace), do: :ok
  def decide(%QueueState{last_error: :not_configured}, _now, _grace), do: :ok

  def decide(%QueueState{last_error: :auth_failed}, _now, _grace) do
    {:fault, :download_client_auth_failed, :error, %{}}
  end

  def decide(%QueueState{last_error: error} = state, now, grace)
      when error == :unreachable or (is_tuple(error) and elem(error, 0) == :offline) do
    if sustained?(state, now, grace) do
      {:fault, :download_client_unreachable, :warning, %{}}
    else
      :ok
    end
  end

  # An `{:offline, since}` error carries its own onset timestamp — measure the
  # outage from it directly. Otherwise measure from the last successful poll; a
  # client that has never succeeded and is currently erroring is treated as
  # sustained (it is down, not blipping).
  defp sustained?(%QueueState{last_error: {:offline, %DateTime{} = since}}, now, grace) do
    DateTime.diff(now, since, :second) >= grace
  end

  defp sustained?(%QueueState{last_successful_poll_at: nil}, _now, _grace), do: true

  defp sustained?(%QueueState{last_successful_poll_at: %DateTime{} = last}, now, grace) do
    DateTime.diff(now, last, :second) >= grace
  end
end
