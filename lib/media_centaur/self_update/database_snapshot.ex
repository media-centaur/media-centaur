defmodule MediaCentaur.SelfUpdate.DatabaseSnapshot do
  @keep 3

  @moduledoc """
  A copy of the database file as it was before an update migrated it.

  `take!/3` writes the copy with SQLite's `VACUUM INTO`, which reads one
  consistent state of a database other connections have open — the
  previous release is still running when an update migrates. The copy
  goes in `snapshots/` beside the database, named for the moment it was
  taken and the version about to migrate:

      media-centaur-20261113T101500Z-before-2.17.0.db

  A snapshot is a whole database, so restoring one is replacing the
  database file with it while the service is stopped. It holds
  everything the database holds, the install's keys included, so it is
  readable by its owner only.

  `sweep/2` keeps the newest #{@keep} and is run by the retention policy in
  `MediaCentaur.SelfUpdate.RetentionPolicies`.
  """

  alias Exqlite.Sqlite3

  @suffix ".db"

  @doc "The snapshot directory for the database at `database_path`."
  @spec directory(String.t()) :: String.t()
  def directory(database_path), do: Path.join(Path.dirname(database_path), "snapshots")

  @doc """
  Copies the database at `database_path` into its snapshot directory and
  returns the copy's path. Raises when the copy cannot be written: the
  caller is about to migrate, and must not without one.
  """
  @spec take!(String.t(), String.t(), DateTime.t()) :: String.t()
  def take!(database_path, version, %DateTime{} = now \\ DateTime.utc_now()) do
    directory = directory(database_path)
    File.mkdir_p!(directory)

    stamp = now |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
    name = "#{Path.basename(database_path, @suffix)}-#{stamp}-before-#{version}#{@suffix}"
    snapshot = Path.join(directory, name)

    {:ok, connection} = Sqlite3.open(database_path)

    try do
      :ok = Sqlite3.execute(connection, "VACUUM INTO '#{String.replace(snapshot, "'", "''")}'")
    after
      Sqlite3.close(connection)
    end

    File.chmod!(snapshot, 0o600)
    snapshot
  end

  @doc """
  Removes all but the newest `keep` snapshots in `directory` and returns
  how many it removed. Snapshot names begin with their timestamp, so the
  newest sort last. Other files are left alone; a missing directory is 0.
  """
  @spec sweep(String.t(), non_neg_integer()) :: non_neg_integer()
  def sweep(directory, keep \\ @keep) do
    case File.ls(directory) do
      {:error, _reason} ->
        0

      {:ok, entries} ->
        entries
        |> Enum.filter(&String.contains?(&1, "-before-"))
        |> Enum.sort(:desc)
        |> Enum.drop(keep)
        |> Enum.count(&(File.rm(Path.join(directory, &1)) == :ok))
    end
  end
end
