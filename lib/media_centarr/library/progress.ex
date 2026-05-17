defmodule MediaCentarr.Library.Progress do
  @moduledoc """
  Public API for the Pillar-2 watch-progress projection (ADR-041,
  Library Schema v2 Phase 3 Task D).

  Active watch-progress state lives in a GenServer-owned ETS table.
  Position-tick updates from `MediaCentarr.Playback.MpvSession` write to
  memory in microseconds via `record/3`; the worker debounce-flushes
  dirty rows to `library_watch_progress` every ~5s (configurable via
  the `:media_centarr, :library_progress_flush_interval_ms` Application
  env key), and synchronously on clean shutdown (`terminate/2`).

  Reads bypass the GenServer entirely:

    * `get/1` does an `:ets.lookup/2` on the worker-owned table. When
      the row isn't in memory, it falls back to a single indexed
      `Repo.get_by/2` query — acceptable for cold paths like first
      detail-modal open. Cold reads do NOT promote the row into
      memory; the in-memory table is reserved for active sessions.

  ## PubSub contract

  All broadcasts go through `MediaCentarr.PubSub`:

    * `{:progress_ticked, %ProgressTicked{}}` on `library:progress`
      for every `record/3` (live UX hook — keeps the progress bar
      ticking forward without page reload).
    * `{:progress_flushed, %ProgressFlushed{}}` on `library:progress`
      for every row flushed to disk (deterministic-sync hook for
      tests and for projections that want to react only after
      persistence).
    * `{:progress_hydrated, %ProgressHydrated{}}` on `library:progress`
      once at the end of the worker's `init/1` — gives tests a
      deterministic hook for boot ordering.
    * `{:watch_completed, playable_item_id}` on `watch_history:events`
      for every `complete/1` call.

  The Library-owned `library:progress` topic exists so progress events
  don't reach across the boundary into the Playback context (which
  owns `playback:events`). See
  `MediaCentarr.Library.Progress.Events` for the typed payloads.

  ## Test-mode behaviour

  The worker isn't started by `MediaCentarr.Application` in `:test`
  env (it's started per-test by the suites that exercise it). When the
  worker isn't running, `get/1` falls through to `Repo.get_by/2` and
  `record/3` / `complete/1` are no-ops — the same safety net the other
  ADR-041 projections rely on.
  """
  alias MediaCentarr.Library.Progress.Worker
  alias MediaCentarr.Library.WatchProgress
  alias MediaCentarr.Repo

  @default_table :library_progress_state

  @doc """
  Records a position tick for an active playback session. Writes land
  in microseconds — the caller directly upserts the in-memory row in
  the public ETS table, so a subsequent `get/1` is guaranteed to see
  the new state without waiting for the GenServer mailbox. The cast
  to the worker only marks the row dirty and schedules a flush.

  Returns `:ok` (no back-pressure — position ticks should never
  block playback).

  ## Concurrency

  Safe under the **single-writer-per-playable-item-id** invariant.
  The hot path is one `MediaCentarr.Playback.MpvSession` per active
  playback session; `MediaCentarr.Playback.SessionRegistry`
  guarantees at most one such session per entity, and
  `playable_item_id` is downstream of the session lifetime.

  Concurrent writers to the same `playable_item_id` from different
  processes are **not** position-monotonic — the ETS write happens
  in the caller process before the cast, so two writers can race on
  the ETS upsert in scheduler-dependent order, and the cast mailbox
  may receive the messages in a different order than the ETS
  writes. Don't fan out `record/3` from `Task.async`-style parallel
  writers for the same id; route ticks through the owning
  `MpvSession` instead.
  """
  @spec record(Ecto.UUID.t(), float(), float()) :: :ok
  def record(playable_item_id, position_seconds, duration_seconds)
      when is_binary(playable_item_id) and is_number(position_seconds) and is_number(duration_seconds) do
    position = position_seconds / 1
    duration = duration_seconds / 1

    write_in_memory(playable_item_id, position, duration, false)
    cast({:record, playable_item_id, position, duration})
  end

  @doc """
  Marks a playable item as completed. Persisted to disk synchronously
  (no debounce — completion is a watershed event) and broadcast on
  `watch_history:events`. Uses `GenServer.call/2` so callers get
  read-after-write semantics against the DB.
  """
  @spec complete(Ecto.UUID.t()) :: :ok
  def complete(playable_item_id) when is_binary(playable_item_id) do
    call({:complete, playable_item_id})
  end

  @doc """
  Reads the watch progress for a `playable_item_id`. Returns the
  in-memory `%WatchProgress{}` shape when an active session has hot
  state, falls back to the persisted row when the row is cold, and
  returns `nil` when there is no record in either store.
  """
  @spec get(Ecto.UUID.t()) :: WatchProgress.t() | nil
  def get(playable_item_id) when is_binary(playable_item_id) do
    case lookup_in_memory_row(playable_item_id) do
      nil -> Repo.get_by(WatchProgress, playable_item_id: playable_item_id)
      row -> row_to_schema(row)
    end
  end

  @doc """
  Returns the in-memory `WatchProgress`-shaped row for the given
  `playable_item_id`, or `nil` when no hot row exists. **Does NOT**
  fall back to the persisted `library_watch_progress` table — use
  `get/1` for read-after-write semantics with DB fallback.

  Exists as a distinct entry point so overlay paths (e.g.
  `Library.list_in_progress/1`'s in-memory overlay, the
  `Playback.ProgressBroadcaster.broadcast/2` overlay) can ask "is
  there a hotter version of this row than what I already loaded
  from disk?" without paying for a per-row DB round-trip when the
  answer is no. The DB read of the same row would be wasteful — the
  caller already holds it.
  """
  @spec lookup_in_memory(Ecto.UUID.t()) :: map() | nil
  def lookup_in_memory(playable_item_id) when is_binary(playable_item_id) do
    case lookup_in_memory_row(playable_item_id) do
      nil -> nil
      row -> row_to_schema(row)
    end
  end

  if Mix.env() == :test do
    @doc """
    Clears the in-memory progress table. **Test-only**: this function
    is compile-time gated to `:test` env and does not exist in the
    `:dev` or `:prod` BEAM bytecode — calling it from non-test code
    is an `UndefinedFunctionError` at compile time. Setup blocks use
    it so each case starts cold without leaking state across tests.
    The persisted `library_watch_progress` rows are unaffected; only
    the worker's hot cache is dropped.
    """
    @spec reset_for_test!() :: :ok
    def reset_for_test! do
      case Process.whereis(Worker) do
        nil -> :ok
        _pid -> GenServer.call(Worker, :reset_for_test!)
      end
    end
  end

  # --- Private ---

  defp cast(message) do
    case Process.whereis(Worker) do
      nil -> :ok
      _pid -> GenServer.cast(Worker, message)
    end
  end

  defp call(message) do
    case Process.whereis(Worker) do
      nil -> :ok
      _pid -> GenServer.call(Worker, message)
    end
  end

  defp lookup_in_memory_row(playable_item_id) do
    case :ets.whereis(@default_table) do
      :undefined ->
        nil

      _ref ->
        case :ets.lookup(@default_table, playable_item_id) do
          [{^playable_item_id, row}] -> row
          [] -> nil
        end
    end
  end

  defp write_in_memory(playable_item_id, position, duration, completed?) do
    case :ets.whereis(@default_table) do
      :undefined ->
        :ok

      _ref ->
        :ets.insert(
          @default_table,
          {playable_item_id,
           %{
             playable_item_id: playable_item_id,
             position_seconds: position,
             duration_seconds: duration,
             completed: completed?,
             last_watched_at: DateTime.utc_now(:second)
           }}
        )

        :ok
    end
  end

  defp row_to_schema(%{
         playable_item_id: pi_id,
         position_seconds: position,
         duration_seconds: duration,
         completed: completed,
         last_watched_at: last_watched_at
       }) do
    %WatchProgress{
      playable_item_id: pi_id,
      position_seconds: position,
      duration_seconds: duration,
      completed: completed,
      last_watched_at: last_watched_at
    }
  end
end
