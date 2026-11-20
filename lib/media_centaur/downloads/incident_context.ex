defmodule MediaCentaur.Downloads.IncidentContext do
  @moduledoc """
  The acquisition subsystem's download-client health probe — the `assess/0` the
  `ErrorReports.Evaluator` polls to own a single `:subsystem` incident for
  download-client connectivity and for the directory finished downloads land
  in (ADR-054).

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

    * `:completed_dir_missing`, `:completed_dir_not_watched` (**warning**) —
      the completed directory of the `prowlarr-stack` wiring in use does not
      exist, or lies outside every media directory, so finished downloads are
      never imported (`Downloads.Wiring.completed_dir_status/0`). Reported
      only while the client is reachable: a connectivity fault comes first.

  `:not_configured` (no client set up) is never a fault.

  The decision is the pure `decide/3` over the producer-graded
  `QueueState.connectivity` (see `MediaCentaur.Downloads.Connectivity`);
  `assess/0` is the thin shell that reads `QueueMonitor`'s public `QueueState`
  (cached in `:persistent_term`, no GenServer call) and the current time, then
  defers to it.

  Reaches the evaluator through the `acquisition` component's composite
  assessor (`MediaCentaur.Acquisition.IncidentContext`), which pairs this
  probe with the search-provider probe (`Search.IncidentContext`).
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.Downloads.QueueMonitor
  alias MediaCentaur.Downloads.QueueState
  alias MediaCentaur.Downloads.Wiring

  # How long a graded outage must have lasted before a connectivity warning
  # opens — long enough that a brief client restart never surfaces, short
  # enough that a real outage shows up promptly. Measured from the outage
  # onset (`{:offline, since}`), which is the first failed poll.
  @unreachable_grace_seconds 180

  @type fault :: {:fault, atom(), :warning | :error, map()}

  @doc "Health probe polled by the diagnostics evaluator. Side-effect-free."
  @spec assess() :: :ok | fault()
  @impl true
  def assess do
    with :ok <- decide(QueueMonitor.state(), DateTime.utc_now(), @unreachable_grace_seconds) do
      completed_dir_fault(Wiring.completed_dir_status())
    end
  end

  @doc "Pure fault decision over `Wiring.completed_dir_status/0`."
  @spec completed_dir_fault(:ok | {:missing | :not_watched, String.t()}) :: :ok | fault()
  def completed_dir_fault(:ok), do: :ok

  def completed_dir_fault({:missing, dir}) do
    {:fault, :completed_dir_missing, :warning,
     %{headline: "Finished downloads directory is missing", dir: dir}}
  end

  def completed_dir_fault({:not_watched, dir}) do
    {:fault, :completed_dir_not_watched, :warning,
     %{headline: "Finished downloads land outside the media directories", dir: dir}}
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
    {:fault, :download_client_auth_failed, :error,
     %{headline: "Download client rejected the credentials"}}
  end

  def decide(%QueueState{connectivity: {:offline, %DateTime{} = since}}, now, grace) do
    if DateTime.diff(now, since, :second) >= grace do
      {:fault, :download_client_unreachable, :warning, %{headline: "Download client unreachable"}}
    else
      :ok
    end
  end

  def decide(%QueueState{}, _now, _grace), do: :ok
end
