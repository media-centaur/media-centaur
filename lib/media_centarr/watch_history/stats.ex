defmodule MediaCentarr.WatchHistory.Stats do
  @moduledoc """
  Pure functions for computing watch history statistics from a list of
  `WatchHistory.Event` structs. No database access — all queries happen
  in the `WatchHistory` facade before calling these functions.
  """

  @cell_size 11
  @cell_gap 2
  @cell_step @cell_size + @cell_gap
  @days 364

  @doc """
  Compute aggregate stats from a list of events.
  Returns %{total_count, total_seconds, streak, heatmap}.
  """
  def compute(events) do
    %{
      total_count: length(events),
      total_seconds: total_seconds(events),
      streak: streak(events),
      heatmap: heatmap(events)
    }
  end

  @doc "Sum duration_seconds across all events."
  def total_seconds([]), do: 0.0
  def total_seconds(events), do: Enum.reduce(events, 0.0, &(&2 + &1.duration_seconds))

  @doc """
  Count consecutive days with at least one completion, ending today or yesterday.
  Multiple completions on the same day count as a single streak day.
  """
  def streak([]), do: 0

  def streak(events) do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    dates =
      events
      |> Enum.map(fn event -> DateTime.to_date(event.completed_at) end)
      |> Enum.uniq()
      |> Enum.sort({:desc, Date})

    start = if today in dates, do: today, else: yesterday
    count_consecutive(dates, start, 0)
  end

  @doc """
  Group completion counts by date for the last 364 days.
  Returns %{Date => count}.
  """
  def heatmap(events) do
    cutoff = Date.add(Date.utc_today(), -(@days - 1))

    events
    |> Enum.filter(fn event ->
      Date.compare(DateTime.to_date(event.completed_at), cutoff) != :lt
    end)
    |> Enum.group_by(fn event -> DateTime.to_date(event.completed_at) end)
    |> Map.new(fn {date, day_events} -> {date, length(day_events)} end)
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
