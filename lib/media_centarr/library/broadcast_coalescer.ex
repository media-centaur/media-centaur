defmodule MediaCentarr.Library.BroadcastCoalescer do
  @moduledoc """
  Coalesces bursts of `:entities_changed` broadcasts into single combined
  emissions. Pipeline ingestion can fire 10-100 broadcasts/sec; this
  reduces them to one per @flush_interval window.

  Latency cost: up to @flush_interval ms before subscribers see the change.
  Subscribers all debounce 500ms+ anyway, so this is invisible end-to-end.
  """
  use GenServer

  alias MediaCentarr.Topics

  @flush_interval 200

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Enqueue a list of entity IDs for the next flush."
  @spec enqueue([term()]) :: :ok
  def enqueue(entity_ids) when is_list(entity_ids) do
    GenServer.cast(__MODULE__, {:enqueue, entity_ids})
  end

  @impl true
  def init(_opts), do: {:ok, %{pending: MapSet.new(), timer: nil}}

  @impl true
  def handle_cast({:enqueue, entity_ids}, state) do
    pending = MapSet.union(state.pending, MapSet.new(entity_ids))

    timer =
      state.timer || Process.send_after(self(), :flush, @flush_interval)

    {:noreply, %{state | pending: pending, timer: timer}}
  end

  @impl true
  def handle_info(:flush, state) do
    if MapSet.size(state.pending) > 0 do
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        Topics.library_updates(),
        {:entities_changed, MapSet.to_list(state.pending)}
      )
    end

    {:noreply, %{pending: MapSet.new(), timer: nil}}
  end
end
