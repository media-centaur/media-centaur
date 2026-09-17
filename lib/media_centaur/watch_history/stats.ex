defmodule MediaCentaur.WatchHistory.Stats do
  @moduledoc """
  Pure shaping for the watch-history aggregates. No database access: the
  `WatchHistory` facade aggregates in SQL — so result-set size does not
  grow with history — and hands the rows here to be shaped.

  `streak_from_dates/1` takes the distinct completion dates; `heatmap_cells/1`
  takes the date-to-count map and lays out the grid.
  """

  @cell_size 11
  @cell_gap 2
  @cell_step @cell_size + @cell_gap
  @days 364

  @doc """
  Count consecutive days with at least one completion, ending today or
  yesterday. The dates arrive unique and descending — distinct
  `date(completed_at)` values straight from the database.
  """
  def streak_from_dates([]), do: 0

  def streak_from_dates(dates) when is_list(dates) do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)
    start = if today in dates, do: today, else: yesterday
    count_consecutive(dates, start, 0)
  end

  @doc """
  Generate the list of SVG cell descriptors for the heatmap grid (last 364 days).
  Each cell: %{date: Date, count: integer, x: integer, y: integer}.
  Weeks go left-to-right; days go top-to-bottom within each week.
  """
  def heatmap_cells(heatmap_data) do
    today = Date.utc_today()
    start_date = Date.add(today, -(@days - 1))

    Date.range(start_date, today)
    |> Enum.chunk_every(7)
    |> Enum.with_index()
    |> Enum.flat_map(fn {week_dates, week_idx} ->
      Enum.with_index(week_dates, fn date, day_idx ->
        %{
          date: date,
          count: Map.get(heatmap_data, date, 0),
          x: week_idx * @cell_step,
          y: day_idx * @cell_step
        }
      end)
    end)
  end

  # --- Private ---

  defp count_consecutive([], _expected, count), do: count

  defp count_consecutive([date | rest], expected, count) do
    if date == expected do
      count_consecutive(rest, Date.add(expected, -1), count + 1)
    else
      count
    end
  end
end
