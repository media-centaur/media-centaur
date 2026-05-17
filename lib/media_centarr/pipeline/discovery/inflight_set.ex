defmodule MediaCentarr.Pipeline.Discovery.InflightSet do
  @moduledoc """
  ETS-backed set of file paths currently in flight through the Discovery
  pipeline.

  Replaces the implicit DB upsert dedup that
  `Watcher.FilePresence.record_file/2` used to provide: when two scans
  100ms apart both spotted the same new file, the second `INSERT`
  collided on `file_path` and the watcher's `MapSet` short-circuited
  the duplicate broadcast. After the library-presence-unification
  campaign that DB-upsert side-effect goes away (Phase 7 deletes the
  table), so dedup moves out of the database and into a dedicated
  in-memory set sized for the pipeline's actual contention window.

  Owned by a separate GenServer (started before `Discovery` in
  `Pipeline.Supervisor`'s `:rest_for_one` tree) so the table outlives
  Broadway producer crashes. If `Discovery` restarts, in-flight claims
  for messages mid-processing remain, and the existing
  `Discovery.process/1 → already_linked?/1` defensive check covers
  any post-restart duplicate that slips through.

  ## Contract

    * `claim/1` returns `true` iff the path was just inserted (caller
      now owns the in-flight slot). Returns `false` when another
      caller is already processing the path — drop the duplicate.
    * `release/1` removes the path so a future detection can re-enter
      the pipeline (e.g. file is deleted and then re-added).
    * Both operations are atomic via `:ets.insert_new/2` /
      `:ets.delete/2` — no GenServer round-trip on the hot path.
  """
  use GenServer

  @table :pipeline_discovery_inflight

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @doc """
  Tries to claim the in-flight slot for `path`. Returns `true` when
  the path was inserted (caller owns it), `false` when another caller
  has already claimed it.
  """
  @spec claim(String.t()) :: boolean()
  def claim(path) when is_binary(path), do: :ets.insert_new(@table, {path})

  @doc """
  Releases `path` so a future detection event for the same path can
  re-enter the pipeline. Safe to call on a path that was never
  claimed (no-op).
  """
  @spec release(String.t()) :: :ok
  def release(path) when is_binary(path) do
    :ets.delete(@table, path)
    :ok
  end

  @doc """
  Returns the current size of the in-flight set. Intended for tests
  and `:telemetry` callers; not part of the hot path.
  """
  @spec size() :: non_neg_integer()
  def size, do: :ets.info(@table, :size)
end
