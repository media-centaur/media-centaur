defmodule MediaCentaur.Acquisition.Pursuits.QueueListener do
  @moduledoc """
  Runs `Observations.observe!/4` for every in-flight target on each queue
  snapshot.

  Observation has to happen on the download client's clock, not the
  decision-maker's. `Pursuits.Watcher` runs every 15 minutes, which is the
  right cadence for *deciding* (its windows are measured in hours) and the
  wrong one for *seeing*: a download that starts and finishes inside those 15
  minutes was never observed at all, so it never got a first-sighting stamp,
  never got its `content_path` captured for `LibraryReconciler`, and never put
  a "Download started" beat on the timeline.

  `QueueMonitor` publishes a `%QueueState{}` on `Topics.acquisition_queue/0`
  every 10 s while someone is watching the page and every 30 s idle. This
  listener subscribes to it and observes against each snapshot. The Watcher
  keeps Policy and dispatch and no longer observes anything.

  `Downloads` cannot depend on `Acquisition` (Boundary), so the trigger lives
  here rather than inside `QueueMonitor` — the same shape as `InboundListener`,
  which bridges `pipeline:publish` into the pursuits domain.

  ## Cost

  One indexed query per snapshot to load the active units with their pursuit
  and current target, then in-memory pairing. Writes only on change: a first
  sighting, a telemetry transition, or an observation window opening or
  closing. A steady download at unchanged health writes nothing. With no
  active pursuits the pass is the query alone, returning no rows.

  Targets are deduplicated before observing, so a season pack whose 38 units
  share one target is observed once and puts one beat on the timeline.
  """

  use GenServer

  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Acquisition.Pursuits.Observations
  alias MediaCentaur.Downloads.QueueState
  alias MediaCentaur.Topics

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    Topics.subscribe(Topics.acquisition_queue())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:queue_state, %QueueState{} = queue_state}, state) do
    observe(queue_state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @doc """
  Observes every in-flight target against one queue snapshot. Returns the
  number of distinct targets observed.

  An unreachable client is a no-op: the snapshot's silence says nothing, and
  `Observations.observe!/4` reads `:unknown` as exactly that. Grading it here
  keeps the decision in one place — `QueueState.answering?/1` — rather than
  having each caller re-derive client health.
  """
  @spec observe(QueueState.t()) :: non_neg_integer()
  def observe(%QueueState{} = queue_state) do
    queue = if QueueState.answering?(queue_state), do: queue_state.items, else: :unknown
    now = DateTime.utc_now(:second)

    Pursuits.list_active_units_with_context()
    |> Enum.reject(fn {_pursuit, _unit, target} -> is_nil(target) end)
    |> Enum.uniq_by(fn {_pursuit, _unit, target} -> target.id end)
    |> Enum.map(fn {pursuit, _unit, target} ->
      Observations.observe!(pursuit, target, queue, now)
    end)
    |> length()
  end
end
