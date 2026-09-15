defmodule MediaCentaur.Library.FileEventHandler do
  @moduledoc """
  Reacts to `{:files_removed, paths}` on the library file-events topic —
  inotify deletions and `Library.AbsenceSweeper` TTL expiry — by running
  `Library.Deletion.cleanup_removed_files/1` off the subscriber process
  and broadcasting the affected entities.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library.{Deletion, Helpers}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  # Test-only sync point: any prior `{:files_removed, _}` message in this
  # GenServer's mailbox is guaranteed to have spawned its cleanup task
  # before the call returns, so a test can then await that task. Without
  # it there is nothing to await yet — the PubSub hop means the message
  # may not have arrived when the test looks.
  @spec __sync_for_test__() :: :ok
  def __sync_for_test__, do: GenServer.call(__MODULE__, :__sync_for_test__)

  @impl true
  def init(_) do
    MediaCentaur.Topics.subscribe(MediaCentaur.Topics.library_file_events())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:files_removed, file_paths}, state) do
    Log.info(:library, "processing removal — #{length(file_paths)} files")

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      entity_ids = Deletion.cleanup_removed_files(file_paths)
      Helpers.broadcast_entities_changed(entity_ids)
    end)

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}
end
