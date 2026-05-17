defmodule MediaCentarr.Library.FilePresence do
  @moduledoc """
  Durable record of "we've observed this file on disk and when".

  One row per file path the watcher has seen in any watch directory.
  This is the single source of truth for file presence — Library
  entity rows (`Library.WatchedFile`, `Library.ExtraFile`) reference
  a FilePresence via foreign key with cascade-delete, so a library
  entity can never exist without a presence record.

  ## Ownership

  This is a Library-domain concept, not a Watcher concept. The
  Watcher is a thin filesystem observer that calls `stamp/2` (or
  `stamp_many/2`) on every detection and lets Library own the
  durable state. See [ADR-045][1] for the full rationale.

  ## Semantics

  * `file_path` is unique. A file at a given path has at most one
    FilePresence row at any time. Re-detecting the same path
    updates `last_seen_at` (UPSERT on conflict).
  * `last_seen_at` is the only presence signal. There is no
    `:present | :absent` state machine; absence is derived by
    comparing `last_seen_at` against the configured TTL via
    `list_stale/1`.
  * Drive-unmount safety: an absence sweep MUST consult
    `MediaCentarr.Watcher.MountStatus` before deleting stale rows
    so an unplugged drive doesn't cascade-wipe the user's library.
    That coordination lives in `Library.AbsenceSweeper`
    (Campaign Phase 6) — this module is pure data, no policy.

  [1]: ../../../decisions/architecture/2026-05-17-045-file-presence-ownership.md
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias MediaCentarr.Repo

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "library_file_presences" do
    field :file_path, :string
    field :watch_dir, :string
    field :last_seen_at, :utc_datetime_usec

    timestamps()
  end

  @doc false
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:file_path, :watch_dir, :last_seen_at])
    |> validate_required([:file_path, :watch_dir, :last_seen_at])
    |> unique_constraint(:file_path)
  end

  # -----------------------------------------------------------------
  # Context API
  # -----------------------------------------------------------------

  @doc """
  Records (or refreshes) the presence of a file. Idempotent — re-
  stamping an existing path updates `last_seen_at` to the supplied
  time (defaulting to `now()`).

  Returns the persisted struct.
  """
  @spec stamp(String.t(), String.t(), DateTime.t() | nil) :: t()
  def stamp(file_path, watch_dir, seen_at \\ DateTime.utc_now()) do
    attrs = %{file_path: file_path, watch_dir: watch_dir, last_seen_at: seen_at}

    {:ok, presence} =
      Repo.insert(
        changeset(attrs),
        on_conflict: [
          set: [last_seen_at: seen_at, watch_dir: watch_dir, updated_at: trunc_seconds(seen_at)]
        ],
        conflict_target: :file_path,
        returning: true
      )

    presence
  end

  @doc """
  Bulk-stamps every path in `paths` under `watch_dir` with a shared
  `seen_at`. Single INSERT … ON CONFLICT … so a 696-file scan
  finishes in one roundtrip instead of 696.
  """
  @spec stamp_many([String.t()], String.t(), DateTime.t() | nil) :: non_neg_integer()
  def stamp_many(paths, watch_dir, seen_at \\ DateTime.utc_now())

  def stamp_many([], _watch_dir, _seen_at), do: 0

  def stamp_many(paths, watch_dir, seen_at) do
    now_truncated = trunc_seconds(seen_at)

    entries =
      Enum.map(paths, fn path ->
        %{
          id: Ecto.UUID.generate(),
          file_path: path,
          watch_dir: watch_dir,
          last_seen_at: seen_at,
          inserted_at: now_truncated,
          updated_at: now_truncated
        }
      end)

    {count, _} =
      Repo.insert_all(__MODULE__, entries,
        on_conflict: [set: [last_seen_at: seen_at, watch_dir: watch_dir, updated_at: now_truncated]],
        conflict_target: :file_path
      )

    count
  end

  @doc """
  Returns the set of file paths currently tracked for `watch_dir`.
  Used by the watcher's scan to dedup against already-seen paths.
  """
  @spec list_paths_for_watch_dir(String.t()) :: MapSet.t(String.t())
  def list_paths_for_watch_dir(watch_dir) do
    from(p in __MODULE__,
      where: p.watch_dir == ^watch_dir,
      select: p.file_path
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns FilePresence rows whose `last_seen_at` is older than the
  given threshold. Caller is responsible for any drive-availability
  guard before acting on the result (don't cascade-delete during an
  unmount).
  """
  @spec list_stale(DateTime.t()) :: [t()]
  def list_stale(threshold) do
    Repo.all(from(p in __MODULE__, where: p.last_seen_at < ^threshold))
  end

  @doc """
  Deletes FilePresence rows by path. Cascade-delete on dependent
  schemas (`WatchedFile`, `ExtraFile`) fires via the FK constraint
  introduced in campaign Phase 3.

  Returns the number of rows removed.
  """
  @spec delete_paths([String.t()]) :: non_neg_integer()
  def delete_paths([]), do: 0

  def delete_paths(paths) when is_list(paths) do
    {count, _} =
      Repo.delete_all(from p in __MODULE__, where: p.file_path in ^paths)

    count
  end

  @doc """
  Resets `last_seen_at` to `now()` for every row under `watch_dir`.
  Returns the number of rows touched.

  Called by `Library.AbsenceSweeper` on a dir's `:available`
  transition so users get a guaranteed full TTL window from the
  moment the drive becomes visible again — files actually present
  on disk are then re-stamped with the same `now()` by the next
  scan, so this reset only matters for files that remain missing.
  """
  @spec reset_last_seen_for_dir(String.t()) :: non_neg_integer()
  def reset_last_seen_for_dir(watch_dir) do
    now = DateTime.utc_now()
    now_truncated = trunc_seconds(now)

    {count, _} =
      Repo.update_all(
        from(p in __MODULE__, where: p.watch_dir == ^watch_dir),
        set: [last_seen_at: now, updated_at: now_truncated]
      )

    count
  end

  @doc """
  Per-watch-dir summary of all tracked presence rows. Returned shape:

      %{watch_dir => %{file_count: non_neg_integer(), earliest_absent_since: DateTime.t()}}

  Pure DB read — no GenServer round-trip. The status-page formatter
  joins this against the live availability map to decide what to
  render: rows for `:unavailable` dirs become "drive offline, N
  files at risk of TTL purge in M days" warnings; rows for available
  dirs are dropped. Replaces the
  `Watcher.AbsencePolicy.at_risk_summary/0` equivalent.

  `earliest_absent_since` is the oldest `last_seen_at` in each dir —
  the file whose TTL countdown started first.
  """
  @spec at_risk_summary() :: %{
          String.t() => %{file_count: non_neg_integer(), earliest_absent_since: DateTime.t()}
        }
  def at_risk_summary do
    Map.new(
      Repo.all(
        from(p in __MODULE__,
          group_by: p.watch_dir,
          select: {p.watch_dir, %{file_count: count(p.id), earliest_absent_since: min(p.last_seen_at)}}
        )
      )
    )
  end

  @type t :: %__MODULE__{}

  # SQLite's `utc_datetime` column resolution is seconds; the
  # `inserted_at` / `updated_at` columns are `:utc_datetime` (no
  # microseconds), while `last_seen_at` is `:utc_datetime_usec`. Cast
  # accordingly so insert_all doesn't choke on precision mismatch.
  defp trunc_seconds(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
end
