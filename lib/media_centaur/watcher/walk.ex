defmodule MediaCentaur.Watcher.Walk do
  @moduledoc """
  Recursive directory walk used by the watcher's scan path.

  Pulled out of `MediaCentaur.Watcher` so the recursion + skip/exclude
  filtering can be exercised with `async: true` against an injected
  filesystem adapter — same pattern as `Watcher.DirValidator`.
  """

  alias MediaCentaur.Watcher.ExcludeDirs

  # Reserved directory names that are never library content, regardless
  # of the user's configured skip list. `.staging` is the documented
  # assembly contract for download clients (prowlarr-stack's SABnzbd
  # verifies/repairs/unpacks there, then renames the finished job out):
  # anything inside is in-progress, watcher-invisible by construction.
  @reserved_skip_dirs [".staging"]

  @type fs_adapter :: %{
          required(:ls) => (String.t() -> {:ok, [String.t()]} | {:error, any()}),
          required(:dir?) => (String.t() -> boolean())
        }

  @doc "Returns the production filesystem adapter."
  @spec real_fs() :: fs_adapter()
  def real_fs do
    %{ls: &File.ls/1, dir?: &File.dir?/1}
  end

  @doc """
  Walks `dir` recursively and returns every file path that is not
  excluded and not under a skip directory.
  """
  @spec walk(String.t(), ExcludeDirs.Prepared.t(), [String.t()], fs_adapter()) :: [String.t()]
  def walk(dir, exclude_dirs, skip_dirs, fs \\ real_fs()) do
    case fs.ls.(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          path = Path.join(dir, entry)

          cond do
            ExcludeDirs.excluded?(path, exclude_dirs) -> []
            fs.dir?.(path) and skip_component?(entry, skip_dirs) -> []
            fs.dir?.(path) -> walk(path, exclude_dirs, skip_dirs, fs)
            true -> [path]
          end
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  True when `path` sits inside a skipped directory — a configured
  skip-dir name (case-insensitive) or one of the reserved names
  (`.staging`). Checks parent components only; the final component is
  the file itself. Shared by the watcher's live-event filter so the
  event path and the scan path can't drift.
  """
  @spec in_skip_dir?(String.t(), [String.t()]) :: boolean()
  def in_skip_dir?(path, skip_dirs) do
    path
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.any?(&skip_component?(&1, skip_dirs))
  end

  defp skip_component?(entry, skip_dirs) do
    entry in @reserved_skip_dirs or String.downcase(entry) in skip_dirs
  end
end
