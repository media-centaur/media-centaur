defmodule MediaCentaur.Watcher.Walk do
  @moduledoc """
  Recursive directory walk used by the watcher's scan path. Returns
  every path under `dir` that is library content, as decided by
  `Watcher.IgnoreRules`.

  Pulled out of `MediaCentaur.Watcher` so the recursion can be
  exercised with `async: true` against an injected filesystem adapter —
  same pattern as `Watcher.DirValidator`.

  The walk calls `IgnoreRules.library_content?/2` on every file, which
  is the same call the inotify event path and the recovery re-emit
  make: one predicate, three boundaries, nothing to drift.
  `IgnoreRules.ignored_dir?/2` prunes a subtree before descending — an
  optimisation that cannot change the answer, because a file under an
  ignored directory already fails the predicate.
  """

  alias MediaCentaur.Watcher.IgnoreRules

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
  Walks `dir` recursively and returns every library-content path
  beneath it.
  """
  @spec walk(String.t(), IgnoreRules.t(), fs_adapter()) :: [String.t()]
  def walk(dir, %IgnoreRules{} = rules, fs \\ real_fs()) do
    case fs.ls.(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          path = Path.join(dir, entry)

          cond do
            fs.dir?.(path) and IgnoreRules.ignored_dir?(path, rules) -> []
            fs.dir?.(path) -> walk(path, rules, fs)
            IgnoreRules.library_content?(path, rules) -> [path]
            true -> []
          end
        end)

      {:error, _} ->
        []
    end
  end
end
