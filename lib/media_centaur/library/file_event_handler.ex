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
end
