defmodule MediaCentaur.Library.Progress do
  @moduledoc """
  Public API for the Pillar-2 watch-progress projection (ADR-041,
  Library Schema v2 Phase 3 Task D).

  Active watch-progress state lives in a GenServer-owned ETS table, one
  row per `{profile_id, playable_item_id}` key (ADR-078). Position-tick
  updates from `MediaCentaur.Playback.MpvSession` write to memory in
  microseconds via `record/4`; the worker debounce-flushes
  dirty rows to `library_watch_progress` every ~5s (configurable via
  the `:media_centaur, :library_progress_flush_interval_ms` Application
  env key), and synchronously on clean shutdown (`terminate/2`).

  Reads bypass the GenServer entirely:

    * `get/2` reads the persisted row with one indexed `Repo.get_by/2`
      and lays the hot offset over it from an `:ets.lookup/2` on the
      worker-owned table. Reads do NOT promote a row into memory; the
      in-memory table is reserved for active sessions.

  ## PubSub contract

  All broadcasts go through `MediaCentaur.Library.Progress.Events`, and
  from there the `MediaCentaur.Topics` transport (ADR-060):

    * `{:progress_ticked, %ProgressTicked{}}` on `library:progress`
      for every `record/4`. No prod subscriber today — the live
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

  A finish (`complete/2`) publishes `{:entity_watch_completed, record,
  actor}` on `library:watch_completed`, through
  `MediaCentaur.Library.ProgressRecords.finish/3`.

  ## The in-memory row is the viewing only

  A hot row carries the offset, the duration and when it was last
  touched. It carries no watched mark: `completed` lives in the database
  and a tick never writes it. A finish removes the hot row. Nothing here
  guards against a repeated finish — the playback session keeps the set
  of items it finished and persists nothing more for them
  (`MediaCentaur.Playback.ProgressWriter.completed?/2`).

  The Library-owned `library:progress` topic exists so progress events
  don't reach across the boundary into the Playback context (which
  owns `playback:events`). See
  `MediaCentaur.Library.Progress.Events` for the typed payloads.

  ## Test-mode behaviour

  The worker isn't started by `MediaCentaur.Application` in `:test`
  env (it's started per-test by the suites that exercise it). When the
  worker isn't running, `get/2` falls through to `Repo.get_by/2` and
  `record/4` / `complete/2` are no-ops — the same safety net the other
  ADR-041 projections rely on.
  """
  alias MediaCentaur.Cache
  alias MediaCentaur.Library.Progress.Worker
  alias MediaCentaur.Profiles.Actor
  alias MediaCentaur.Library.WatchProgress
  alias MediaCentaur.Repo

  @default_table :library_progress_state

  @typedoc "The in-memory row's key: one profile's progress on one playable item."
  @type key :: {Ecto.UUID.t(), Ecto.UUID.t()}

  @doc """
  Records a position tick of `profile_id`'s session on a playable item.
  Writes land in microseconds — the caller directly upserts the
  in-memory row in the public ETS table, so a subsequent `get/2` is
  guaranteed to see
  the new state without waiting for the GenServer mailbox. The cast
  to the worker only marks the row dirty and schedules a flush.

  Returns `:ok` (no back-pressure — position ticks should never
  block playback).

  ## Concurrency

  Safe under the **single-writer-per-key** invariant. The hot path is
  one `MediaCentaur.Playback.MpvSession` per active playback session;
  `MediaCentaur.Playback.SessionRegistry` guarantees at most one such
  session per entity, and the key is downstream of the session
  lifetime.

  Concurrent writers to the same key from different
  processes are **not** position-monotonic — the ETS write happens
  in the caller process before the cast, so two writers can race on
  the ETS upsert in scheduler-dependent order, and the cast mailbox
  may receive the messages in a different order than the ETS
  writes. Don't fan out `record/4` from `Task.async`-style parallel
  writers for the same key; route ticks through the owning
  `MpvSession` instead.
  """
  @spec record(Ecto.UUID.t(), Ecto.UUID.t(), float(), float()) :: :ok
  def record(profile_id, playable_item_id, position_seconds, duration_seconds)
      when is_binary(profile_id) and is_binary(playable_item_id) and is_number(position_seconds) and
             is_number(duration_seconds) do
    position = position_seconds / 1
    duration = duration_seconds / 1
    key = {profile_id, playable_item_id}

    write_in_memory(key, position, duration)
    cast({:record, key, position, duration})
  end

  @doc """
  Playback finished a playable item for the `actor`'s profile: the watched
  mark is set, the viewing is over (offset zero, the hot row removed), the
  series watch position moves there, and the finish event is published —
  every time, see `MediaCentaur.Library.ProgressRecords.finish/3`.
  Persisted synchronously (no debounce); uses `GenServer.call/2` so
  callers get read-after-write semantics against the DB.
  """
  @spec complete(Actor.t(), Ecto.UUID.t()) :: :ok
  def complete(%Actor{} = actor, playable_item_id) when is_binary(playable_item_id),
    do: call({:complete, {actor.profile_id, playable_item_id}, actor})

  @doc """
  Reads `profile_id`'s watch progress on a `playable_item_id`: the
  persisted row, with the live offset of an active session laid over it
  (`overlay_in_memory/1`). `completed` is therefore always the
  database's. A hot row not flushed yet reads as an unmarked row at the
  live offset; `nil` when there is no record in either store.
  """
  @spec get(Ecto.UUID.t(), Ecto.UUID.t()) :: WatchProgress.t() | nil
  def get(profile_id, playable_item_id) when is_binary(profile_id) and is_binary(playable_item_id) do
    case Repo.get_by(WatchProgress, profile_id: profile_id, playable_item_id: playable_item_id) do
      nil -> lookup_in_memory({profile_id, playable_item_id})
      persisted -> overlay_in_memory(persisted)
    end
  end

  # In-memory `WatchProgress`-shaped row for `key`, or `nil` when no hot
  # row exists. Does NOT read the persisted table.
  @spec lookup_in_memory(key()) :: map() | nil
  defp lookup_in_memory(key) do
    case lookup_in_memory_row(key) do
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

  The hot row carries no watched mark, so `completed` is the record's own.

  The single overlay seam shared by the Continue Watching list
  (`Library.list_in_progress/2`) and the modal broadcast
  (`Playback.ProgressBroadcaster.broadcast/3`).
  """
  @spec overlay_in_memory(map()) :: map()
  def overlay_in_memory(%{profile_id: profile_id, playable_item_id: playable_item_id} = record)
      when is_binary(profile_id) and is_binary(playable_item_id) do
    case lookup_in_memory({profile_id, playable_item_id}) do
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
      call(:reset_for_test!)
    end
  end

  # --- Private ---

  # A cast to the worker's name is `:ok` whether or not it runs (it does
  # not under :test); a call to it degrades the same way.
  defp cast(message), do: GenServer.cast(Worker, message)

  defp call(message) do
    GenServer.call(Worker, message)
  catch
    :exit, {:noproc, _call} -> :ok
  end

  defp lookup_in_memory_row(key) do
    Cache.with_table(
      @default_table,
      fn ->
        case :ets.lookup(@default_table, key) do
          [{^key, row}] -> row
          [] -> nil
        end
      end,
      fn -> nil end
    )
  end

  defp write_in_memory({profile_id, playable_item_id} = key, position, duration) do
    case :ets.whereis(@default_table) do
      :undefined ->
        :ok

      _ref ->
        :ets.insert(
          @default_table,
          {key,
           %{
             profile_id: profile_id,
             playable_item_id: playable_item_id,
             position_seconds: position,
             duration_seconds: duration,
             last_watched_at: DateTime.utc_now(:second)
           }}
        )

        :ok
    end
  end

  defp row_to_schema(%{
         profile_id: profile_id,
         playable_item_id: pi_id,
         position_seconds: position,
         duration_seconds: duration,
         last_watched_at: last_watched_at
       }) do
    %WatchProgress{
      profile_id: profile_id,
      playable_item_id: pi_id,
      position_seconds: position,
      duration_seconds: duration,
      last_watched_at: last_watched_at
    }
  end
end
