defmodule MediaCentarr.Acquisition.QueueMonitor do
  @moduledoc """
  Polls the configured download client every 5 seconds and broadcasts
  the resulting queue snapshot. Replaces per-LiveView polling so multiple
  consumers (Downloads page + Library upcoming zone) can react to the
  same data without each opening its own connection.

  ## Cache + broadcast

  - Each successful poll caches the snapshot in `:persistent_term` for
    cheap synchronous reads via `MediaCentarr.Acquisition.queue_snapshot/0`.
  - Each successful poll also broadcasts `{:queue_snapshot, items}` on
    `Topics.acquisition_queue()` so subscribers can refresh live.

  ## Polling cadence

  - 5 seconds when `Capabilities.download_client_ready?/0` is true
  - 30 seconds otherwise (avoids hammering an unconfigured client; gives
    the user time to wire one up without missing many polls)

  ## Failure handling

  Errors from the download client are logged and the previous snapshot
  is kept in cache. Transient failures don't blank the UI.
  """
  use GenServer

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.QueueItem
  alias MediaCentarr.Capabilities
  alias MediaCentarr.Topics

  @cache_key {__MODULE__, :snapshot}
  @poll_active_ms 5_000
  @poll_idle_ms 30_000

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

  @impl GenServer
  def init(_opts) do
    Process.send_after(self(), :poll, 0)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    if Capabilities.download_client_ready?() do
      poll_and_broadcast()
      Process.send_after(self(), :poll, @poll_active_ms)
    else
      Process.send_after(self(), :poll, @poll_idle_ms)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:poll_now, state) do
    if Capabilities.download_client_ready?(), do: poll_and_broadcast()
    {:noreply, state}
  end

  defp poll_and_broadcast do
    case Acquisition.list_downloads(:all) do
      {:ok, items} ->
        active = Enum.reject(items, &(&1.state == :completed))
        :persistent_term.put(@cache_key, active)

        Phoenix.PubSub.broadcast(
          MediaCentarr.PubSub,
          Topics.acquisition_queue(),
          {:queue_snapshot, active}
        )

      {:error, :not_configured} ->
        # Lost configuration mid-flight — clear cache so subscribers
        # don't render stale rows.
        :persistent_term.put(@cache_key, [])

      {:error, reason} ->
        Log.warning(:library, "queue monitor poll failed: #{inspect(reason)}")
    end
  end
end
