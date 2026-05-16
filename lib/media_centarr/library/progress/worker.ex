defmodule MediaCentarr.Library.Progress.Worker do
  @moduledoc """
  GenServer that owns active watch-progress state in an ETS table and
  debounce-flushes dirty rows to `library_watch_progress` (ADR-041,
  Library Schema v2 Phase 3 Task D).

  This is the only writer of `WatchProgress` rows on the live playback
  hot path — `MediaCentarr.Playback.MpvSession` records position ticks
  via `Library.Progress.record/3`, which casts into this GenServer.
  Position updates land in microseconds (an ETS upsert + a dirty-set
  membership flip); a `Process.send_after/3` timer batches the writes
  into a single `Ecto.Multi` upsert every `@default_flush_interval_ms`.

  Reads bypass the GenServer entirely — see `MediaCentarr.Library.Progress.get/1`.

  ## Lifecycle

    * `init/1` opens the ETS table (named per `:table` arg, default
      `:library_progress_state`) and hydrates it from the DB by
      streaming every `WatchProgress` row with `completed: false`. The
      hydration step broadcasts `{:progress_hydrated, %ProgressHydrated{count: n}}`
      on the `library:progress` topic via
      `MediaCentarr.Library.Progress.Events.broadcast/1` (the typed-event
      chokepoint) as a deterministic observability hook for boot
      ordering.
    * `handle_cast({:record, id, pos, dur}, state)` upserts the in-memory
      row, marks it dirty, broadcasts
      `{:progress_ticked, %ProgressTicked{playable_item_id: id, position_seconds: pos}}`
      on `library:progress` (preserves the live-progress-bar UX), and
      schedules a `:flush` after the configured interval if no timer is
      already pending.
    * `handle_info(:flush, state)` wraps the batched upsert in a
      single `Repo.transaction/1` via `persist_rows/1` —
      `Library.upsert_watch_progress_by_playable_item_id!/1` is
      called per row inside the transaction so a mid-flush failure
      rolls back the whole batch. On success, the dirty set is
      cleared and `{:progress_flushed, %ProgressFlushed{playable_item_id: id}}`
      is broadcast on `library:progress` per row. On failure the
      dirty set is left populated so the next flush retries.
    * `handle_call({:complete, id}, _from, state)` writes a
      `completed: true` row directly (no debounce — completion is a
      watershed event) and broadcasts
      `{:watch_completed, playable_item_id}` on `watch_history:events`.
    * `terminate/2` synchronously flushes the dirty set so a clean
      shutdown doesn't lose state.

  ## PubSub contract

  All progress broadcasts go through
  `MediaCentarr.Library.Progress.Events.broadcast/1` on the
  `library:progress` topic. The typed payloads are
  `%ProgressTicked{playable_item_id, position_seconds}`,
  `%ProgressFlushed{playable_item_id}`, and
  `%ProgressHydrated{count}`. Completion broadcasts ride the
  `watch_history:events` topic as `{:watch_completed, playable_item_id}`
  to stay aligned with the WatchHistory consumer set.

  ## Configuration

    * `:flush_interval_ms` — overrides the application env key
      `:media_centarr, :library_progress_flush_interval_ms`. Tests
      collapse to ~50 ms; production defaults to 5_000 ms.
    * `:table` — ETS table atom; defaults to `:library_progress_state`.
      Tests that need an isolated table (terminate/2 + hydration cases)
      pass a unique atom to avoid colliding with the application
      singleton.
    * `:name` — process name; defaults to `__MODULE__`.
  """
  use GenServer

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Progress.Events
  alias MediaCentarr.Library.Progress.Events.{ProgressFlushed, ProgressHydrated, ProgressTicked}
  alias MediaCentarr.Library.WatchProgress
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

  require MediaCentarr.Log, as: Log

  @default_table :library_progress_state
  @default_flush_interval_ms 5_000

  # --- Public child_spec / start_link ---

  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    # Trap exits so `terminate/2` runs on supervised shutdown — the
    # debounced flush has to be a synchronous best-effort write before
    # the process dies, otherwise a clean stop loses pending state.
    Process.flag(:trap_exit, true)

    table = Keyword.get(opts, :table, @default_table)
    flush_interval_ms = resolve_flush_interval(opts)

    :ets.new(table, [:set, :public, :named_table, read_concurrency: true])

    count = hydrate_from_db(table)

    Events.broadcast(%ProgressHydrated{count: count})

    {:ok,
     %{
       table: table,
       dirty: MapSet.new(),
       flush_timer: nil,
       flush_interval_ms: flush_interval_ms
     }}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    # Benign synchronous probe — tests use this to flush prior casts
    # through the mailbox without introspecting state.
    {:reply, :ok, state}
  end

  def handle_call(:reset_for_test!, _from, state) do
    :ets.delete_all_objects(state.table)
    state = cancel_timer(state)
    {:reply, :ok, %{state | dirty: MapSet.new()}}
  end

  def handle_call({:complete, playable_item_id}, _from, state) do
    now = DateTime.utc_now(:second)

    case Library.find_or_create_watch_progress_by_playable_item_id(playable_item_id) do
      {:ok, record} ->
        # Flush any pending dirty position for this PI first so we
        # mark-completed against the latest known position, not a
        # stale just-created row at position 0.
        record =
          case lookup_row(state.table, playable_item_id) do
            nil ->
              record

            in_memory ->
              {:ok, updated} =
                MediaCentarr.Repo.update(
                  MediaCentarr.Library.WatchProgress.update_changeset(record, %{
                    position_seconds: in_memory.position_seconds,
                    duration_seconds: in_memory.duration_seconds
                  })
                )

              updated
          end

        {:ok, _completed} = Library.mark_watch_completed(record)

        upsert_in_memory(
          state.table,
          playable_item_id,
          record.position_seconds,
          record.duration_seconds,
          now,
          true
        )

        Phoenix.PubSub.broadcast(
          MediaCentarr.PubSub,
          Topics.watch_history_events(),
          {:watch_completed, playable_item_id}
        )

        dirty = MapSet.delete(state.dirty, playable_item_id)
        {:reply, :ok, %{state | dirty: dirty}}

      {:error, reason} ->
        Log.warning(
          :playback,
          "Library.Progress.complete/1 — could not resolve watch_progress: #{inspect(reason)}"
        )

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:record, playable_item_id, position, duration}, state) do
    # The public-API caller already wrote the row into the public ETS
    # table before casting (see `Library.Progress.record/3`) for
    # read-after-write semantics. We re-upsert here so direct callers
    # (e.g. tests that bypass the public API to exercise the worker
    # under a non-default table name) also end up with a row to flush.
    # The write is idempotent — the latest position wins regardless of
    # which path placed it.
    now = DateTime.utc_now(:second)
    upsert_in_memory(state.table, playable_item_id, position, duration, now, false)

    Events.broadcast(%ProgressTicked{
      playable_item_id: playable_item_id,
      position_seconds: position
    })

    dirty = MapSet.put(state.dirty, playable_item_id)
    state = schedule_flush(%{state | dirty: dirty})

    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    # Failure model: the batched upsert runs inside one
    # `Repo.transaction/1`. On success we broadcast per row and
    # clear the dirty set. On failure we log, leave the dirty set
    # populated, and let the next `:flush` retry — partial writes
    # never leak past the transaction boundary.
    case flush_dirty(state) do
      {:ok, flushed_ids} ->
        Enum.each(flushed_ids, &broadcast_flushed/1)
        {:noreply, %{state | dirty: MapSet.new(), flush_timer: nil}}

      {:error, reason} ->
        Log.warning(
          :playback,
          "Library.Progress.Worker — flush transaction failed; dirty set preserved for retry: #{inspect(reason)}"
        )

        # Re-arm the flush timer so the next interval retries the
        # batch. Without this, a failed flush would leave dirty
        # rows stranded until the next `:record` cast happens to
        # schedule a new timer.
        state = schedule_flush(%{state | flush_timer: nil})
        {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    # Synchronously persist pending rows so a clean shutdown doesn't
    # drop in-memory state. We do NOT broadcast on terminate — there
    # is no reliable subscriber after the supervisor decides to stop
    # the process. Wrapped in a try/rescue so a DB error during
    # shutdown is logged rather than crashing the supervision tree.
    try do
      case flush_dirty(state) do
        {:ok, _flushed_ids} ->
          :ok

        {:error, reason} ->
          Log.warning(
            :playback,
            "Library.Progress.Worker — terminate flush failed: #{inspect(reason)}"
          )
      end
    rescue
      error ->
        Log.warning(
          :playback,
          "Library.Progress.Worker — terminate flush raised: #{Exception.message(error)}"
        )
    end

    :ok
  end

  # --- Helpers ---

  defp resolve_flush_interval(opts) do
    Keyword.get(
      opts,
      :flush_interval_ms,
      Application.get_env(
        :media_centarr,
        :library_progress_flush_interval_ms,
        @default_flush_interval_ms
      )
    )
  end

  defp upsert_in_memory(table, playable_item_id, position, duration, last_watched_at, completed?) do
    :ets.insert(
      table,
      {playable_item_id,
       %{
         playable_item_id: playable_item_id,
         position_seconds: position,
         duration_seconds: duration,
         completed: completed?,
         last_watched_at: last_watched_at
       }}
    )
  end

  defp schedule_flush(%{flush_timer: nil, flush_interval_ms: interval_ms} = state) do
    timer = Process.send_after(self(), :flush, interval_ms)
    %{state | flush_timer: timer}
  end

  defp schedule_flush(state), do: state

  defp cancel_timer(%{flush_timer: nil} = state), do: state

  defp cancel_timer(%{flush_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | flush_timer: nil}
  end

  defp flush_dirty(%{dirty: dirty, table: table}) do
    case MapSet.to_list(dirty) do
      [] ->
        {:ok, []}

      ids ->
        rows =
          ids
          |> Enum.map(fn id -> lookup_row(table, id) end)
          |> Enum.reject(&is_nil/1)

        case persist_rows(rows) do
          :ok -> {:ok, Enum.map(rows, & &1.playable_item_id)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp lookup_row(table, playable_item_id) do
    case :ets.lookup(table, playable_item_id) do
      [{^playable_item_id, row}] -> row
      [] -> nil
    end
  end

  defp persist_rows(rows) do
    # Wrap the batched upsert in one transaction. A mid-flush
    # failure rolls back the whole batch — partial DB writes would
    # desync from the in-memory ETS state and silently drop the
    # un-persisted dirty entries.
    case Repo.transaction(fn ->
           Enum.each(rows, &Library.upsert_watch_progress_by_playable_item_id!/1)
         end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_flushed(playable_item_id) do
    Events.broadcast(%ProgressFlushed{playable_item_id: playable_item_id})
  end

  defp hydrate_from_db(table) do
    import Ecto.Query

    WatchProgress
    |> where([wp], wp.completed == false)
    |> Repo.all()
    |> Enum.reduce(0, fn record, count ->
      :ets.insert(
        table,
        {record.playable_item_id,
         %{
           playable_item_id: record.playable_item_id,
           position_seconds: record.position_seconds,
           duration_seconds: record.duration_seconds,
           completed: record.completed,
           last_watched_at: record.last_watched_at
         }}
      )

      count + 1
    end)
  end
end
