defmodule MediaCentarr.Acquisition.Health do
  @moduledoc """
  Classifies the *quality* of an active queue item by observed
  throughput over a rolling window, plus a few related "stuck" cases
  (metadata fetch hung, queued for too long).

  Distinct from `MediaCentarr.Acquisition.QueueItem.state/0`:

  - `state` is what the download client says — `:downloading`, `:queued`,
    `:stalled` (the client reports no peers), etc.
  - `health` is *our* judgement on whether a `:downloading` item is
    making meaningful progress, or a `:queued` item has been waiting too
    long, or a magnet is taking forever to resolve.

  The two coexist: a queue item can be `state: :downloading,
  health: :soft_stall` — qBittorrent thinks it's downloading, we think
  it's barely moving.

  ## Decision tree

  First match wins. See `classify/3`.

  | input | rule | output |
  |---|---|---|
  | `state == :queued` | history age ≥ 30 min | `:queued_long` |
  | `state == :queued` | else | `nil` |
  | raw `status == "metaDL"` | history age ≥ 5 min | `:meta_stuck` |
  | raw `status == "metaDL"` | else | `:warming_up` |
  | `state != :downloading` | (any) | `nil` |
  | `size_left == nil` | (any) | `nil` |
  | history empty or < 2 min old | (any) | `:warming_up` |
  | `delta_10min == 0` | (any) | `:frozen` |
  | `delta_1hr` not computable | (any) | `:warming_up` |
  | `delta_1hr < 100 MB` | (any) | `:soft_stall` |
  | `delta_1hr < 500 MB` | (any) | `:slow` |
  | else | (any) | `:healthy` |

  ## Configuration

  All thresholds are module attributes here. If a real-world user hits
  a wrong threshold, lift them into TOML config — there are no users
  of these constants outside this module.
  """

  alias MediaCentarr.Acquisition.QueueItem

  @type status ::
          :healthy
          | :warming_up
          | :slow
          | :soft_stall
          | :frozen
          | :meta_stuck
          | :queued_long

  @type sample :: {integer(), non_neg_integer()}

  @warmup_us 2 * 60 * 1_000_000
  @frozen_us 10 * 60 * 1_000_000
  @hour_us 60 * 60 * 1_000_000
  @meta_stuck_us 5 * 60 * 1_000_000
  @queued_long_us 30 * 60 * 1_000_000

  @soft_stall_bytes 100 * 1024 * 1024
  @slow_bytes 500 * 1024 * 1024

  @doc """
  Returns the health window (in microseconds) the monitor must keep in
  history. Anything older than this is unused by `classify/3`. Exposed
  so `QueueMonitor` can truncate without copying the constant.
  """
  @spec max_window_us() :: pos_integer()
  def max_window_us, do: @hour_us

  @doc """
  Classifies an item given its monotonic-time history (newest first)
  and the current monotonic time.

  Returns a `t:status/0` atom or `nil` (no special indicator — let the
  state badge speak alone).
  """
  @spec classify(QueueItem.t(), [sample()], integer()) :: status() | nil
  def classify(%QueueItem{} = item, history, now) when is_integer(now) do
    cond do
      item.state == :queued ->
        if history_age_us(history, now) >= @queued_long_us, do: :queued_long

      item.status == "metaDL" ->
        if history_age_us(history, now) >= @meta_stuck_us, do: :meta_stuck, else: :warming_up

      item.state != :downloading ->
        nil

      is_nil(item.size_left) ->
        nil

      history_age_us(history, now) < @warmup_us ->
        :warming_up

      true ->
        classify_by_throughput(history, now)
    end
  end

  defp classify_by_throughput(history, now) do
    delta_10 = delta_window(history, now, @frozen_us)
    delta_1h = delta_window(history, now, @hour_us)

    cond do
      delta_10 == 0 -> :frozen
      is_nil(delta_1h) -> :warming_up
      delta_1h < @soft_stall_bytes -> :soft_stall
      delta_1h < @slow_bytes -> :slow
      true -> :healthy
    end
  end

  # Returns how long (in µs) the oldest sample we have predates `now`,
  # or 0 if history is empty.
  defp history_age_us([], _now), do: 0

  defp history_age_us(history, now) do
    {oldest_ts, _} = List.last(history)
    now - oldest_ts
  end

  # Returns bytes downloaded over the last `window_us` microseconds, or
  # nil if we don't have a sample old enough to span the window.
  #
  # Computed as `size_left_then - size_left_now`. Newest sample is the
  # head of `history`; "then" is the *newest* sample older than the
  # window cutoff (so we measure as close to a full window as possible).
  defp delta_window([], _now, _window_us), do: nil

  defp delta_window([{_, size_left_now} | _] = history, now, window_us) do
    cutoff = now - window_us

    case Enum.find(history, fn {ts, _} -> ts <= cutoff end) do
      nil -> nil
      {_, size_left_then} -> max(size_left_then - size_left_now, 0)
    end
  end

  @doc """
  Long-form label for the Downloads page secondary line.
  """
  @spec label(status()) :: String.t()
  def label(:healthy), do: "Healthy"
  def label(:warming_up), do: "Starting…"
  def label(:slow), do: "Slow — under 500 MB in past hour"
  def label(:soft_stall), do: "Less than 100 MB in past hour"
  def label(:frozen), do: "No progress in 10 minutes"
  def label(:meta_stuck), do: "Fetching metadata for over 5 min — magnet may be dead"
  def label(:queued_long), do: "Queued for over 30 minutes"

  @doc """
  Short label for upcoming-card tooltips. One or two words.
  """
  @spec short_label(status()) :: String.t()
  def short_label(:healthy), do: "Healthy"
  def short_label(:warming_up), do: "Starting"
  def short_label(:slow), do: "Slow"
  def short_label(:soft_stall), do: "Stuck"
  def short_label(:frozen), do: "Stuck"
  def short_label(:meta_stuck), do: "Magnet stuck"
  def short_label(:queued_long), do: "Queued long"

  @doc """
  daisyUI badge variant for the secondary line on the Downloads page.
  Returns `nil` for `:healthy` and `:warming_up` — those cases don't
  warrant chrome of their own.
  """
  @spec badge_variant(status()) :: String.t() | nil
  def badge_variant(:soft_stall), do: "warning"
  def badge_variant(:frozen), do: "warning"
  def badge_variant(:meta_stuck), do: "warning"
  def badge_variant(:slow), do: "ghost"
  def badge_variant(:queued_long), do: "ghost"
  def badge_variant(:healthy), do: nil
  def badge_variant(:warming_up), do: nil

  @doc """
  Whether a status is "stuck enough" that a future automation pass
  (`AutoGrabPolicy`) should consider replacing the release.

  Today nothing reads this — it's the forward-compatible API for the
  next slice. Defining it now means the next slice is purely additive.
  """
  @spec degraded?(status() | nil) :: boolean()
  def degraded?(:soft_stall), do: true
  def degraded?(:frozen), do: true
  def degraded?(:meta_stuck), do: true
  def degraded?(_), do: false

  @doc """
  Whether a status is in the "slow but progressing" middle tier.
  Distinct from `degraded?/1` — `:slow` is informational only.
  """
  @spec slow?(status() | nil) :: boolean()
  def slow?(:slow), do: true
  def slow?(_), do: false
end
