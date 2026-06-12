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
    * **Threshold** — `QueueMonitor` already absorbs a single failed poll as a
      `{:transient_failure, _}` blip, and the grace window
      (`@unreachable_grace_seconds`) additionally requires the graded outage to
      have lasted before it faults; only sustained loss surfaces.
    * **Lifecycle** — the evaluator auto-resolves the incident when `assess/0`
      reports `:ok` again on recovery.

  ## Fault conditions

    * `:download_client_auth_failed` (**error**) — credentials rejected. Not
      transient; surfaces immediately (no grace).
    * `:download_client_unreachable` (**warning**) — the client is graded
      `{:offline, since}` and the outage onset is older than the grace window.

  `:not_configured` (no client set up) is never a fault.

  The decision is the pure `decide/3` over the producer-graded
  `QueueState.connectivity` (see `MediaCentaur.Downloads.Connectivity`);
  `assess/0` is the thin shell that reads `QueueMonitor`'s public `QueueState`
  (cached in `:persistent_term`, no GenServer call) and the current time, then
  defers to it.

  Like `SelfUpdate.IncidentContext`, this fulfils the `IncidentContext` `assess/0`
  contract **structurally rather than via `@behaviour`**: the registry binds
  assessors by `function_exported?(module, :assess, 0)` purely by name, so a
  subsystem reports health without a compile-time `Downloads → ErrorReports`
  edge. Registered under the `:acquisition` component in
  `config :media_centaur, :diagnostics_contributors`.
  """

  alias MediaCentaur.Downloads.QueueMonitor
  alias MediaCentaur.Downloads.QueueState

  # How long a graded outage must have lasted before a connectivity warning
  # opens — long enough that a brief client restart never surfaces, short
  # enough that a real outage shows up promptly. Measured from the outage
  # onset (`{:offline, since}`), which is the first failed poll.
  @unreachable_grace_seconds 180

  @type fault :: {:fault, atom(), :warning | :error, map()}

  @doc "Health probe polled by the diagnostics evaluator. Side-effect-free."
  @spec assess() :: :ok | fault()
  def assess do
    decide(QueueMonitor.state(), DateTime.utc_now(), @unreachable_grace_seconds)
  end

  @doc """
  Pure fault decision over the producer-graded connectivity.

    * `state` — the latest `%QueueState{}` (`QueueMonitor.state/0`).
    * `now` — current time.
    * `grace_seconds` — how long the graded outage must have lasted, measured
      from its onset, before a `:download_client_unreachable` warning opens.

  Auth failures ignore the grace window; healthy, initializing, transient-blip
  and unconfigured states never fault.
  """
  @spec decide(QueueState.t(), DateTime.t(), pos_integer()) :: :ok | fault()
  def decide(%QueueState{connectivity: :auth_failed}, _now, _grace) do
    {:fault, :download_client_auth_failed, :error, %{}}
  end

  def decide(%QueueState{connectivity: {:offline, %DateTime{} = since}}, now, grace) do
    if DateTime.diff(now, since, :second) >= grace do
      {:fault, :download_client_unreachable, :warning, %{}}
    else
      :ok
    end
  end

  def decide(%QueueState{}, _now, _grace), do: :ok
end
