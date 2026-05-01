defmodule MediaCentarr.Watcher.DeletionBuffer do
  @moduledoc """
  Pure container for paths the watcher saw deletion events for, awaiting
  a debounce flush.

  The buffer collects deletions during a sliding-window timer. When the
  timer fires the GenServer drains the buffer and broadcasts the flushed
  paths. Keeping this state in a struct means timer-cancellation is the
  GenServer's only side-effect concern; the bookkeeping itself is pure
  and async-testable.
  """

  defstruct entries: %{}

  @type t :: %__MODULE__{entries: %{String.t() => String.t()}}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Records a deleted path along with the watch dir it came from."
  @spec add(t(), String.t(), String.t()) :: t()
  def add(%__MODULE__{entries: entries} = buffer, path, watch_dir) do
    %{buffer | entries: Map.put(entries, path, watch_dir)}
  end

  @doc "Returns the buffered paths in arbitrary order."
  @spec paths(t()) :: [String.t()]
  def paths(%__MODULE__{entries: entries}), do: Map.keys(entries)

  @doc "Returns true when the buffer holds no entries."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{entries: entries}), do: map_size(entries) == 0

  @doc "Returns a fresh empty buffer."
  @spec reset(t()) :: t()
  def reset(%__MODULE__{}), do: new()
end
