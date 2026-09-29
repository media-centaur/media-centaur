defmodule MediaCentaur.EpisodeMapping.FileEventHandler do
  @moduledoc """
  Drops awaiting-queue rows for files the library reports removed
  (`{:files_removed, paths}` on `Topics.library_file_events()`): a file
  deleted from disk or retracted by an ignore rule has no position left
  to decide.

  The EpisodeMapping half of what `Review.FileEventHandler` does for the
  Review queue — each context clears its own table, and `Library` cannot
  call either.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.EpisodeMapping

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc false
  # Test-only sync point: any prior message in this GenServer's mailbox is
  # processed before the call returns.
  @spec __sync_for_test__() :: :ok
  def __sync_for_test__, do: GenServer.call(__MODULE__, :__sync_for_test__)

  @impl true
  def init(_) do
    MediaCentaur.Topics.subscribe(MediaCentaur.Topics.library_file_events())
    {:ok, nil}
  end

  @impl true
  def handle_info({:files_removed, file_paths}, state) do
    case EpisodeMapping.drop_awaiting_files(file_paths) do
      {:ok, 0} ->
        :ok

      {:ok, count} ->
        Log.info(:pipeline, "dropped #{count} awaiting file(s) — no longer library content")
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}
end
