defmodule MediaCentaur.Library.Progress do
  @moduledoc """
  Public API for the Pillar-2 watch-progress projection (ADR-041,
  Library Schema v2 Phase 3 Task D).

  Active watch-progress state lives in a GenServer-owned ETS table.
  Position-tick updates from `MediaCentaur.Playback.MpvSession` write to
  memory in microseconds via `record/3`; the worker debounce-flushes
  dirty rows to `library_watch_progress` every ~5s (configurable via
  the `:media_centaur, :library_progress_flush_interval_ms` Application
  env key), and synchronously on clean shutdown (`terminate/2`).

  Reads bypass the GenServer entirely:

    * `get/1` does an `:ets.lookup/2` on the worker-owned table. When
      the row isn't in memory, it falls back to a single indexed
      `Repo.get_by/2` query — acceptable for cold paths like first
      detail-modal open. Cold reads do NOT promote the row into
      memory; the in-memory table is reserved for active sessions.

  ## PubSub contract

  All broadcasts go through `MediaCentaur.PubSub`:

    * `{:progress_ticked, %ProgressTicked{}}` on `library:progress`
      for every `record/3`. No prod subscriber today — the live
      progress bar is driven by `playback:events`
      (`:entity_progress_updated`); per ADR-041 this is a deterministic
      per-tick hook for tests and a seam for future activity-only
      projections.
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
  `MediaCentaur.Library.Progress.Events` for the typed payloads.

  ## Test-mode behaviour

  The worker isn't started by `MediaCentaur.Application` in `:test`
  env (it's started per-test by the suites that exercise it). When the
  worker isn't running, `get/1` falls through to `Repo.get_by/2` and
  `record/3` / `complete/1` are no-ops — the same safety net the other
  ADR-041 projections rely on.
  """
  alias MediaCentaur.Library.Progress.Worker
  alias MediaCentaur.Library.WatchProgress
  alias MediaCentaur.Repo

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
  The hot path is one `MediaCentaur.Playback.MpvSession` per active
  playback session; `MediaCentaur.Playback.SessionRegistry`
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

    # Preserve a completion already recorded for this item. mpv keeps
    # reporting position ticks through the tail of a finished item, so
    # a tick must never downgrade `completed: true` back to false —
    # doing so defeats the completion idempotency guard in
    # `MpvSession.maybe_mark_completed_via_progress/3`, which then
    # re-runs completion (and re-broadcasts `{:watch_completed, _}`)
    # every tick. We read the hot row only: a *cold* completed row is
    # not hydrated into memory (see Worker.init/1), so a fresh rewatch
    # session correctly starts at `completed: false`. Un-completing is
    # an explicit action on a different path.
    write_in_memory(playable_item_id, position, duration, hot_completed?(playable_item_id))
    cast({:record, playable_item_id, position, duration})
  end

  defp hot_completed?(playable_item_id) do
    match?(%{completed: true}, lookup_in_memory_row(playable_item_id))
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

  # In-memory `WatchProgress`-shaped row for `playable_item_id`, or `nil`
  # when no hot row exists. Does NOT fall back to the persisted table (unlike
  # `get/1`). Sole caller is `overlay_in_memory/1`, which asks "is there a
  # hotter version of this already-loaded DB row?" without a per-row DB
  # round-trip when the answer is no.
  @spec lookup_in_memory(Ecto.UUID.t()) :: map() | nil
  defp lookup_in_memory(playable_item_id) when is_binary(playable_item_id) do
    case lookup_in_memory_row(playable_item_id) do
      nil -> nil
      row -> row_to_schema(row)
    end
  end

  @doc """
  Overlays live session state onto a DB-loaded `WatchProgress` record so a
  caller rendering during active playback sees the live-ticking
  `position_seconds` / `duration_seconds` / `last_watched_at` without a
  per-tick DB round trip. Returns the record unchanged when no hot row
  exists (the common case for rows without an active session).

  `completed` is deliberately **not** overlaid — it is authoritative in the
  DB. The hot row's `completed` is a within-session idempotency signal
  (false for cold rows, set true only when `complete/1` runs during the
  session — see `record/3`), so overlaying it would downgrade a completion
  recorded on another path back to `false`: a manual "mark watched" toggle
  writes the DB but never the hot row, so its completion would be silently
  reverted on the next tick and only reappear after a page reload. Because
  `complete/1` persists to the DB synchronously *before* touching the hot
  row, the DB `completed` is never staler than memory — trusting it loses
  nothing.

  The single overlay seam shared by the Continue Watching list
  (`Library.list_in_progress/1`) and the modal broadcast
  (`Playback.ProgressBroadcaster.broadcast/2`).
  """
  @spec overlay_in_memory(map()) :: map()
  def overlay_in_memory(%{playable_item_id: playable_item_id} = record)
      when is_binary(playable_item_id) do
    case lookup_in_memory(playable_item_id) do
      nil ->
        record

      hot ->
        %{
          record
          | position_seconds: hot.position_seconds,
            duration_seconds: hot.duration_seconds,
            last_watched_at: hot.last_watched_at
        }
    end
  end

  def overlay_in_memory(record), do: record

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
