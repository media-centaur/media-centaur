defmodule MediaCentarr.Acquisition.QueueMonitor do
  @moduledoc """
  Polls the configured download client and broadcasts the resulting
  queue snapshot. Replaces per-LiveView polling so multiple consumers
  (Downloads page + Library upcoming zone) share a single connection.

  ## Cache + broadcast

  - Each successful poll caches the snapshot in `:persistent_term` for
    cheap synchronous reads via `MediaCentarr.Acquisition.queue_snapshot/0`.
  - Each successful poll also broadcasts `{:queue_snapshot, items}` on
    `Topics.acquisition_queue()` so subscribers can refresh live.

  ## Subscriber-aware cadence

  The poll interval scales with whether anyone is watching:

  - **1 s** when at least one LiveView is subscribed AND the download
    client is ready — the row needs to feel real-time.
  - **5 s** when ready but nobody is watching — keeps the cache warm
    without burning request budget on the client.
  - **30 s** when the client is offline — back off so the eventual
    reconfigure picks up within a reasonable window.

  Subscribers register implicitly via `Acquisition.subscribe_queue/0`,
  which calls `register_subscriber/1`. We `Process.monitor/1` each one
  and drop them on `:DOWN`.

  ## Failure handling

  Errors from the download client are logged and the previous snapshot
  is kept in cache. Transient failures don't blank the UI.

  ## Health classification

  After each successful poll the cached snapshot is enriched with a
  `:health` field per item via `MediaCentarr.Acquisition.HealthHistory`.
  The throughput history needed to classify items lives in this
  GenServer's state; only this module updates it.
  """
  use GenServer

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.HealthHistory
  alias MediaCentarr.Acquisition.QueueItem
  alias MediaCentarr.Capabilities
  alias MediaCentarr.Topics

  @cache_key {__MODULE__, :snapshot}
  @poll_watched_ms 1_000
  @poll_idle_ms 5_000
  @poll_offline_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the latest cached queue snapshot. Synchronous, no GenServer
  call — reads `:persistent_term`. Returns `[]` before the first poll.
  """
  @spec snapshot() :: [QueueItem.t()]
  def snapshot do
    case :persistent_term.get(@cache_key, nil) do
      nil -> []
      items when is_list(items) -> items
    end
  end

  @doc """
  Triggers an immediate poll without disturbing the scheduled cadence.
  Used when an external event makes us suspect the cached snapshot is
  stale — e.g. a user just configured the download client and we'd
  otherwise wait up to 30s for the next idle-cadence tick.
  """
  @spec poll_now() :: :ok
  def poll_now, do: GenServer.cast(__MODULE__, :poll_now)

  @doc """
  Registers `pid` as an active subscriber so the next poll uses the
  watched cadence. Idempotent — re-registering the same pid is a no-op.
  Pid is dropped automatically when the process exits.

  Called from `Acquisition.subscribe_queue/0`; LiveViews should not
  call this directly.
  """
  @spec register_subscriber(pid()) :: :ok
  def register_subscriber(pid) when is_pid(pid), do: GenServer.cast(__MODULE__, {:register, pid})

  @doc """
  Returns the poll cadence in milliseconds for the given subscriber
  count and download-client-ready flag. Pure — extracted for unit
  testing the contract without spinning up a GenServer.
  """
  @spec cadence_ms(non_neg_integer(), boolean()) :: pos_integer()
  def cadence_ms(_subscribers, false), do: @poll_offline_ms
  def cadence_ms(0, true), do: @poll_idle_ms
  def cadence_ms(_subscribers, true), do: @poll_watched_ms

  @impl GenServer
  def init(_opts) do
    Process.send_after(self(), :poll, 0)
    {:ok, %{subscribers: %{}, history: %{}}}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    ready? = Capabilities.download_client_ready?()
    state = if ready?, do: poll_and_broadcast(state), else: state
    Process.send_after(self(), :poll, cadence_ms(map_size(state.subscribers), ready?))
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast(:poll_now, state) do
    state = if Capabilities.download_client_ready?(), do: poll_and_broadcast(state), else: state
    {:noreply, state}
  end

  def handle_cast({:register, pid}, state) do
    if Map.has_key?(state.subscribers, pid) do
      {:noreply, state}
    else
      ref = Process.monitor(pid)
      {:noreply, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
    end
  end

  defp poll_and_broadcast(state) do
    case Acquisition.list_downloads(:all) do
      {:ok, items} ->
        active = Enum.reject(items, &(&1.state == :completed))
        now = System.monotonic_time(:microsecond)
        {history, enriched} = HealthHistory.update(state.history, active, now)

        :persistent_term.put(@cache_key, enriched)

        Phoenix.PubSub.broadcast(
          MediaCentarr.PubSub,
          Topics.acquisition_queue(),
          {:queue_snapshot, enriched}
        )

        %{state | history: history}

      {:error, :not_configured} ->
        :persistent_term.put(@cache_key, [])
        %{state | history: %{}}

      {:error, reason} ->
        Log.warning(:library, "queue monitor poll failed: #{inspect(reason)}")
        state
    end
  end
end
