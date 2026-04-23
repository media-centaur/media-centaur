defmodule MediaCentarr.Watcher.ExcludeDirs do
  @moduledoc """
  Pure path-matching helper for the watcher's exclude-dir filter.

  Exclude lists are precompiled into a `%Prepared{}` struct once (per watch
  dir, cached on the GenServer state) so the per-path check doesn't rebuild
  `dir <> "/"` on every call. The struct wrapping is load-bearing: the
  `excluded?/2` head pattern-matches `%Prepared{}`, so a stray raw-list
  caller crashes at the function boundary with a clear stack trace rather
  than buried inside an anonymous fn.

  A path is excluded when it equals an exclude dir exactly, or sits
  underneath one (matched via `dir <> "/"` to avoid `/foo` matching
  `/foobar`).
  """

  defmodule Prepared do
    @moduledoc false
    @enforce_keys [:entries]
    defstruct [:entries]

    @type t :: %__MODULE__{entries: [{String.t(), String.t()}]}
  end

  @doc """
  Precompiles a list of absolute directory paths into match-ready form.

  The resulting struct is safe to stash on GenServer state and reuse
  across many `excluded?/2` calls.
  """
  @spec prepare([String.t()]) :: Prepared.t()
  def prepare(exclude_dirs) when is_list(exclude_dirs) do
    %Prepared{entries: Enum.map(exclude_dirs, fn dir -> {dir, dir <> "/"} end)}
  end

  @doc """
  Returns `true` when `path` is at or below any of the prepared exclude dirs.
  """
  @spec excluded?(String.t(), Prepared.t()) :: boolean()
  def excluded?(path, %Prepared{entries: entries}) when is_binary(path) do
    Enum.any?(entries, fn {dir, dir_slash} ->
      path == dir or String.starts_with?(path, dir_slash)
    end)
  end
end
