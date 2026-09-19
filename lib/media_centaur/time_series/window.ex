defmodule MediaCentaur.TimeSeries.Window do
  @moduledoc """
  The six spans a viewer can select and, for each, the bar width, the
  number of bars and the stored resolution the bars are summed from.

  | Window | Bar | Bars | From |
  |---|---|---|---|
  | `:"5m"` | 10 s | 30 | `:"10s"` |
  | `:"1h"` | 1 min | 60 | `:"1m"` |
  | `:"5h"` | 5 min | 60 | `:"1m"` × 5 |
  | `:"1d"` | 20 min | 72 | `:"10m"` × 2 |
  | `:"1w"` | 2 h | 84 | `:"1h"` × 2 |
  | `:"1mo"` | 12 h | 60 | `:"1h"` × 12 |

  Bars of 20 minutes and wider are *locally aligned*: they start on the
  machine's local midnight rather than on the UTC epoch (`Fold`).
  """

  alias MediaCentaur.TimeSeries.Resolution

  @type t :: :"5m" | :"1h" | :"5h" | :"1d" | :"1w" | :"1mo"

  @table %{
    "5m": %{bar: 10, bars: 30, resolution: :"10s"},
    "1h": %{bar: 60, bars: 60, resolution: :"1m"},
    "5h": %{bar: 300, bars: 60, resolution: :"1m"},
    "1d": %{bar: 1_200, bars: 72, resolution: :"10m"},
    "1w": %{bar: 7_200, bars: 84, resolution: :"1h"},
    "1mo": %{bar: 43_200, bars: 60, resolution: :"1h"}
  }

  @all [:"5m", :"1h", :"5h", :"1d", :"1w", :"1mo"]

  @spec all() :: [t()]
  def all, do: @all

  @spec parse(term()) :: {:ok, t()} | :error
  def parse(label) when is_binary(label) do
    case Enum.find(@all, &(Atom.to_string(&1) == label)) do
      nil -> :error
      window -> {:ok, window}
    end
  end

  def parse(_other), do: :error

  @spec bar_seconds(t()) :: pos_integer()
  def bar_seconds(window), do: Map.fetch!(@table, window).bar

  @spec bars(t()) :: pos_integer()
  def bars(window), do: Map.fetch!(@table, window).bars

  @spec resolution(t()) :: Resolution.t()
  def resolution(window), do: Map.fetch!(@table, window).resolution

  @spec span_seconds(t()) :: pos_integer()
  def span_seconds(window), do: bar_seconds(window) * bars(window)

  @doc "Bars of 20 minutes and wider start on the local midnight, not the epoch."
  @spec local_aligned?(t()) :: boolean()
  def local_aligned?(window), do: bar_seconds(window) >= 1_200
end
