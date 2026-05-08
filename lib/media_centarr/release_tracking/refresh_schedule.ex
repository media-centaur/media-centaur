defmodule MediaCentarr.ReleaseTracking.RefreshSchedule do
  @moduledoc """
  Pure scheduling helper for `ReleaseTracking.Refresher`'s timer loops.

  `Process.send_after(self(), msg, interval)` is wall-clock based but
  tied to process uptime. On every node restart the timer resets, so a
  single fixed-interval loop can drift indefinitely if the node bounces
  faster than the interval. `next_delay_ms/2` collapses that drift by
  consulting a persisted "last completed" timestamp and scheduling the
  next tick at `max(0, interval - elapsed)`.
  """

  @doc """
  Returns the milliseconds to wait before the next tick.

  `nil` last-completed timestamp returns 0 — i.e. run the loop
  immediately, no prior cycle to wait for.
  """
  @spec next_delay_ms(DateTime.t() | nil, non_neg_integer()) :: non_neg_integer()
  def next_delay_ms(nil, _interval_ms), do: 0

  def next_delay_ms(%DateTime{} = last_completed_at, interval_ms)
      when is_integer(interval_ms) and interval_ms >= 0 do
    elapsed_ms = DateTime.diff(DateTime.utc_now(), last_completed_at, :millisecond)
    max(0, interval_ms - elapsed_ms)
  end
end
