defmodule MediaCentaur.SelfUpdate.StagingSweep do
  @moduledoc """
  Removes leftover upgrade-staging directories.

  Each update attempt extracts into `{staging_root}/{version}-{random}/`
  and cleans up after itself on success or cancel — but a crash mid-update
  strands the directory (50MB–1GB each). The retention sweep removes any
  staging entry older than #{div(2 * 24 * 3600, 3600)} hours; a directory
  that old can't belong to an in-flight attempt (updates run in minutes).

  The root is configurable via `:upgrade_staging_root` (tests point it at
  a tmp dir so the sweep never touches the real user cache).
  """

  @default_max_age_seconds 2 * 24 * 3600

  @doc "The staging root shared with `MediaCentaur.SelfUpdate.Updater`."
  @spec default_root() :: String.t()
  def default_root do
    Application.get_env(:media_centaur, :upgrade_staging_root) ||
      Path.join([System.user_home!(), ".cache", "media-centaur", "upgrade-staging"])
  end

  @doc """
  Removes entries under `root` whose mtime is older than `max_age_seconds`.
  Returns the number of entries removed. A missing root is 0.
  """
  @spec sweep(String.t(), pos_integer()) :: non_neg_integer()
  def sweep(root \\ default_root(), max_age_seconds \\ @default_max_age_seconds) do
    case File.ls(root) do
      {:error, _} ->
        0

      {:ok, entries} ->
        cutoff = System.os_time(:second) - max_age_seconds

        entries
        |> Enum.map(&Path.join(root, &1))
        |> Enum.filter(&stale?(&1, cutoff))
        |> Enum.count(fn path -> match?({:ok, _}, File.rm_rf(path)) end)
    end
  end

  defp stale?(path, cutoff) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime < cutoff
      {:error, _} -> false
    end
  end
end
