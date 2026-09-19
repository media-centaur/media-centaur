defmodule MediaCentaur.TimeSeries.Resolution do
  @moduledoc """
  The four stored bucket widths and how long each is kept. Every event is
  counted into all four at once, so there is no roll-up pass; the sweep
  removes rows past their retention.

  | Resolution | Width | Kept |
  |---|---|---|
  | `:"10s"` | 10 s | 1 h |
  | `:"1m"` | 60 s | 6 h |
  | `:"10m"` | 600 s | 2 d |
  | `:"1h"` | 3600 s | 31 d |

  Bucket starts are epoch seconds aligned down to the width, in UTC.
  """

  @type t :: :"10s" | :"1m" | :"10m" | :"1h"

  @widths %{"10s": 10, "1m": 60, "10m": 600, "1h": 3_600}
  @retention %{"10s": 3_600, "1m": 6 * 3_600, "10m": 2 * 86_400, "1h": 31 * 86_400}

  @spec all() :: [t()]
  def all, do: [:"10s", :"1m", :"10m", :"1h"]

  @spec width(t()) :: pos_integer()
  def width(resolution), do: Map.fetch!(@widths, resolution)

  @spec retention(t()) :: pos_integer()
  def retention(resolution), do: Map.fetch!(@retention, resolution)

  @spec bucket_start(t(), integer()) :: integer()
  def bucket_start(resolution, unix_seconds) do
    width = width(resolution)
    unix_seconds - Integer.mod(unix_seconds, width)
  end
end
