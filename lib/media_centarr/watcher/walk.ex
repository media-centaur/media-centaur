defmodule MediaCentarr.Watcher.Walk do
  @moduledoc """
  Recursive directory walk used by the watcher's scan path.

  Pulled out of `MediaCentarr.Watcher` so the recursion + skip/exclude
  filtering can be exercised with `async: true` against an injected
  filesystem adapter — same pattern as `Watcher.DirValidator`.
  """

  alias MediaCentarr.Watcher.ExcludeDirs

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
            fs.dir?.(path) and String.downcase(entry) in skip_dirs -> []
            fs.dir?.(path) -> walk(path, exclude_dirs, skip_dirs, fs)
            true -> [path]
          end
        end)

      {:error, _} ->
        []
    end
  end
end
