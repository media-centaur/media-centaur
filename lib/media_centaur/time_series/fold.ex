defmodule MediaCentaur.TimeSeries.Fold do
  @moduledoc """
  Rows of one key, folded into the bars of a `Window`: fixed-length
  columns per schema field, zero-filled, plus window totals (sum for
  `:sum` fields, max for `:max` fields).

  Bars are anchored so the last bar is the one in progress. Narrow bars
  (under 20 minutes) anchor on the epoch; wide bars anchor on the local
  midnight from `LocalDay`, so a 12-hour bar runs midnight to noon where
  the machine is. Pass `utc_offset:` to pin the zone (tests); by default
  it is read from the operating system.

  The result is what a tenant turns into a strip chart frame:

      %{
        window: :"1h", bar_seconds: 60,
        starts: [unix, …],                 # one per bar, ascending
        columns: %{requests: [int, …], …}, # same length as starts
        totals: %{requests: int, …}
      }
  """

  alias MediaCentaur.TimeSeries.{LocalDay, Schema, Store, Window}

  @type series :: %{
          window: Window.t(),
          bar_seconds: pos_integer(),
          starts: [integer()],
          columns: %{atom() => [integer()]},
          totals: %{atom() => integer()}
        }

  @spec series(atom(), Schema.t(), term(), Window.t(), integer(), keyword()) :: series()
  def series(table, %Schema{} = schema, key, window, now, opts \\ []) do
    bar = Window.bar_seconds(window)
    bars = Window.bars(window)
    anchor = anchor(window, now, opts)
    current = Integer.floor_div(now - anchor, bar)
    first = current - bars + 1
    starts = Enum.map(first..current//1, &(anchor + &1 * bar))

    rows = Store.rows(table, Window.resolution(window), key, hd(starts), now)

    empty = Map.new(schema.names, &{&1, :array.new(bars, default: 0)})

    filled =
      Enum.reduce(rows, empty, fn {start, values}, acc ->
        index = Integer.floor_div(start - anchor, bar) - first

        Enum.reduce(schema.fields, acc, fn {name, kind}, acc ->
          Map.update!(acc, name, fn column ->
            :array.set(index, combine(kind, :array.get(index, column), values[name]), column)
          end)
        end)
      end)

    columns = Map.new(filled, fn {name, column} -> {name, :array.to_list(column)} end)

    totals =
      Map.new(schema.fields, fn
        {name, :sum} -> {name, Enum.sum(columns[name])}
        {name, :max} -> {name, Enum.max(columns[name], fn -> 0 end)}
      end)

    %{window: window, bar_seconds: bar, starts: starts, columns: columns, totals: totals}
  end

  defp combine(:sum, current, value), do: current + value
  defp combine(:max, current, value), do: max(current, value)

  defp anchor(window, now, opts) do
    if Window.local_aligned?(window) do
      offset = Keyword.get_lazy(opts, :utc_offset, &LocalDay.utc_offset_seconds/0)
      LocalDay.start_of_day(now, offset)
    else
      0
    end
  end
end
