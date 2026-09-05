defmodule MediaCentaur.ReleaseTracking.RefreshSchedule do
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

  `nil` last-completed timestamp returns the floor — i.e. run the loop
  as soon as allowed, no prior cycle to wait for. `now` is injectable so
  tests can assert exact delays instead of padding for wall-clock skew.

  `floor_ms:` (default 0) is the soonest the tick may fire. A loop that
  restarts after a crash with an overdue timestamp would otherwise tick
  immediately, crash again on the same transient (a module mid-reload, a
  database mid-migration) and exhaust its supervisor's restart budget —
  which took the whole application down once (2026-09-05).
  """
  @spec next_delay_ms(DateTime.t() | nil, non_neg_integer(), DateTime.t(), keyword()) ::
          non_neg_integer()
  def next_delay_ms(last_completed_at, interval_ms, now \\ DateTime.utc_now(), opts \\ [])

  def next_delay_ms(nil, _interval_ms, _now, opts), do: Keyword.get(opts, :floor_ms, 0)

  def next_delay_ms(%DateTime{} = last_completed_at, interval_ms, %DateTime{} = now, opts)
      when is_integer(interval_ms) and interval_ms >= 0 do
    elapsed_ms = DateTime.diff(now, last_completed_at, :millisecond)
    max(Keyword.get(opts, :floor_ms, 0), interval_ms - elapsed_ms)
  end
end
