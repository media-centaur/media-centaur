defmodule MediaCentaur.Library.MoveMatcher do
  @moduledoc """
  Pure move detection: decides whether a newly-seen file is the same
  content as a file the library already tracks at a different path.

  A move is recognised by matching the file's path **relative to its
  watch directory** plus its byte size. Relative path survives the
  common "moved the whole tree to a new drive" case — the layout under
  the watch dir is preserved — and size disambiguates when two watch
  dirs hold the same relative path. Renames and re-encodes are
  deliberately out of scope: a genuine move preserves both signals, and
  covering renames would need content hashing (heavy I/O) for a long
  tail of cases.

  Pre-feature `FilePresence` rows carry no size (`nil`); those fall back
  to a relative-path-only match so the first move after upgrade still
  relinks.

  This module is pure — no DB, no filesystem. The caller supplies the
  candidate rows and is responsible for confirming the old path is
  actually gone (move vs. copy) before acting on a `{:move, row}`.
  """

  @type existing :: %{
          :file_path => String.t(),
          :watch_dir => String.t(),
          :size => non_neg_integer() | nil,
          optional(any()) => any()
        }
  @type new_file :: %{
          :path => String.t(),
          :watch_dir => String.t(),
          :size => non_neg_integer() | nil
        }

  @doc """
  Returns `{:move, existing_row}` when exactly one candidate matches the
  new file's relative path (and size, when both are known), or `:no_match`
  when nothing matches or the match is ambiguous (two+ candidates). When
  in doubt we bail to `:no_match` and let the file import as new — a wrong
  relink is worse than a redundant import.
  """
  @spec match(new_file(), [existing()]) :: {:move, existing()} | :no_match
  def match(%{path: path, watch_dir: watch_dir, size: size}, existing_rows) do
    relpath = relative_path(path, watch_dir)

    existing_rows
    |> Enum.filter(fn row ->
      relative_path(row.file_path, row.watch_dir) == relpath and
        size_compatible?(size, row.size)
    end)
    |> case do
      [single] -> {:move, single}
      _zero_or_many -> :no_match
    end
  end

  @doc "Path of `file_path` relative to its `watch_dir`."
  @spec relative_path(String.t(), String.t()) :: String.t()
  def relative_path(file_path, watch_dir), do: Path.relative_to(file_path, watch_dir)

  # A pre-feature row (nil size) can only be matched on relative path.
  defp size_compatible?(_new_size, nil), do: true
  defp size_compatible?(new_size, old_size), do: new_size == old_size
end
