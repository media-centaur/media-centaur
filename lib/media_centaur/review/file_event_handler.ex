defmodule MediaCentaur.Review.FileEventHandler do
  @moduledoc """
  Reacts to the library's file events on `Topics.library_file_events()`:

    * `{:files_removed, paths}` → drops those paths from the review queue;
    * `{:file_linked, path}` / `{:file_parked, path}` → the file is in the
      library or the reconciliation queue, so its review item closes
      (`Review.file_linked/1`, `Review.file_parked/1`);
    * `{:file_not_linked, outcome}` → the item returns to the queue with
      the reason (`Review.file_not_linked/1`).

  The link outcomes are the only way an approved item closes — see
  `MediaCentaur.Review`, "An item closes on its file's link outcome".

  The review queue holds files awaiting a decision. When a file stops
  being library content there is no decision left to make, so its row
  goes. Two things produce that event and neither used to clear the
  queue: the watcher observing a deletion (or
  `Library.AbsenceSweeper` expiring an absence), which left a row
  pointing at nothing on disk; and `Watcher.Rescan.retract_ignored/0`,
  which retracts paths a newly-added ignore rule now covers.

  Mirrors `Library.FileEventHandler`, which consumes the same event for
  the library's own bookkeeping. Two subscribers rather than one
  handler because the contexts own different tables and `Library`
  cannot call `Review` — `Review` depends on `Library`, not the
  reverse.

  Each reaction runs inline in the GenServer: it is one or two writes by
  path, so there is nothing to hand to a task, and staying synchronous
  is what makes `__sync_for_test__/0` a complete await.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Review

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc false
  # Test-only sync point: any prior message in this
  # GenServer's mailbox is guaranteed processed before the call returns.
  @spec __sync_for_test__() :: :ok
  def __sync_for_test__, do: GenServer.call(__MODULE__, :__sync_for_test__)

  @impl true
  def init(_) do
    MediaCentaur.Topics.subscribe(MediaCentaur.Topics.library_file_events())
    {:ok, nil}
  end

  @impl true
  def handle_info({:files_removed, file_paths}, state) do
    case Review.drop_pending_files(file_paths) do
      {:ok, 0} ->
        :ok

      {:ok, count} ->
        Log.info(:review, "dropped #{count} queued file(s) — no longer library content")
    end

    {:noreply, state}
  end

  def handle_info({:file_linked, file_path}, state) do
    Review.file_linked(file_path)
    {:noreply, state}
  end

  def handle_info({:file_parked, file_path}, state) do
    Review.file_parked(file_path)
    {:noreply, state}
  end

  def handle_info({:file_not_linked, outcome}, state) do
    Review.file_not_linked(outcome)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}
end
