defmodule MediaCentarr.StatsHelpers do
  @moduledoc """
  Shared utility functions for pipeline stats GenServers.

  Used by `Pipeline.Stats` and `ImagePipeline.Stats` to avoid
  duplicating windowed throughput calculation, status derivation,
  and error formatting.
  """

  @doc "Removes completions older than `window_ms` from the sliding window."
  def prune_window(completions, now, window_ms) do
    cutoff = now - window_ms
    Enum.filter(completions, fn {ts, _duration} -> ts >= cutoff end)
  end

  @doc "Calculates events per second from the completions window."
  def calculate_throughput([], _window_ms), do: 0.0

  def calculate_throughput(completions, window_ms) do
    count = length(completions)
    Float.round(count / (window_ms / 1_000), 1)
  end

  @doc "Calculates average duration in milliseconds from completions."
  def calculate_avg_duration([]), do: nil

  def calculate_avg_duration(completions) do
    {total, count} =
      Enum.reduce(completions, {0, 0}, fn {_ts, duration}, {sum, n} ->
        {sum + duration, n + 1}
      end)

    avg_native = total / count
    Float.round(System.convert_time_unit(round(avg_native), :native, :millisecond) / 1, 1)
  end

  @doc "Derives status atom from current activity and error state."
  def derive_status(active_count, last_error, now, window_ms, saturated_threshold) do
    has_recent_error =
      case last_error do
        {_msg, error_time} -> now - error_time < window_ms
        nil -> false
      end

    cond do
      active_count > 0 and has_recent_error -> :erroring
      active_count >= saturated_threshold -> :saturated
      active_count > 0 -> :active
      true -> :idle
    end
  end

  @doc "Formats an error reason as a string."
  def format_error_reason(reason) when is_binary(reason), do: reason
  def format_error_reason(reason), do: inspect(reason)
end
