defmodule MediaCentaur.TimeSeries.Schema do
  @moduledoc """
  A store's counter fields, in tuple order. Each field is `:sum` (added on
  every event) or `:max` (kept as the largest seen). A row in the table is
  `{key, v1, v2, …}` with the key at position 1 and field `i` at position
  `i + 1`; the schema precomputes the positions so `Store.add/5` builds
  its ETS operations without walking a keyword list per event.

  Build one at compile time with a module attribute:

      @schema Schema.new(requests: :sum, failed: :sum, latency_max_ms: :max)
  """

  @type kind :: :sum | :max
  @type t :: %__MODULE__{
          fields: [{atom(), kind()}],
          names: [atom()],
          positions: %{atom() => pos_integer()},
          sums: [atom()],
          maxes: [atom()]
        }

  @enforce_keys [:fields, :names, :positions, :sums, :maxes]
  defstruct [:fields, :names, :positions, :sums, :maxes]

  @max_fields 8

  @doc "The most counter fields a schema may declare (the store's match specs are sized for it)."
  @spec max_fields() :: pos_integer()
  def max_fields, do: @max_fields

  @spec new([{atom(), kind()}]) :: t()
  def new(fields) when is_list(fields) and fields != [] and length(fields) <= @max_fields do
    names = Keyword.keys(fields)

    %__MODULE__{
      fields: fields,
      names: names,
      positions: names |> Enum.with_index(2) |> Map.new(),
      sums: for({name, :sum} <- fields, do: name),
      maxes: for({name, :max} <- fields, do: name)
    }
  end

  @doc "Turns a row tuple's values back into a map keyed by field name."
  @spec values(t(), tuple()) :: %{atom() => integer()}
  def values(%__MODULE__{names: names}, row) when is_tuple(row) do
    names |> Enum.with_index(1) |> Map.new(fn {name, index} -> {name, elem(row, index)} end)
  end

  @doc "A row tuple for `key` from a values map (missing fields are 0)."
  @spec row(t(), term(), %{atom() => integer()}) :: tuple()
  def row(%__MODULE__{names: names}, key, values) do
    List.to_tuple([key | Enum.map(names, &Map.get(values, &1, 0))])
  end
end
