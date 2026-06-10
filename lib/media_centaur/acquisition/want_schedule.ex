defmodule MediaCentaur.Acquisition.WantSchedule do
  @moduledoc """
  Pure re-search scheduling for release-tracking wants (ADR-056 Q6):
  the stepped back-off that decides whether a want is *search-due* at a
  tick, and the patience window that decides whether its quality floor
  is elevated (Q4).

  The schedule follows availability reality — releases appear within
  hours-to-days of airing, so the hot window is aggressive; after a
  week unfound the cadence backs off, but it **never gives up**:
  stopping is a user dismissal, not a timeout.

      want age          re-search interval
      0–48 h            30 min   (the corpus freshness window)
      48 h – 7 d        4 h
      7 – 30 d          24 h
      30 d +            7 d, forever

  Patience expiry forces due: when the window lapses, the floor drops
  from the ceiling back to the user's minimum, which obsoletes every
  "unfound at 4K" negative search — so the want re-searches immediately
  rather than waiting out its current band.
  """

  @hour 3600
  @day 24 * @hour

  @doc """
  Whether the want should be searched at `now`. Never-searched wants
  are due immediately; otherwise the age-band interval applies, with
  the patience-expiry override.
  """
  @spec due?(struct(), non_neg_integer(), DateTime.t()) :: boolean()
  def due?(%{last_searched_at: nil}, _patience_hours, _now), do: true

  def due?(want, patience_hours, %DateTime{} = now) do
    patience_expired_since_last_search?(want, patience_hours, now) or
      interval_elapsed?(want, now)
  end

  @doc """
  Whether the want's quality floor is elevated to the ceiling — true
  inside the patience window (`now < wanted_since + patience_hours`).
  Patience `0` means no elevation ever.
  """
  @spec floor_elevated?(struct(), non_neg_integer(), DateTime.t()) :: boolean()
  def floor_elevated?(_want, 0, _now), do: false

  def floor_elevated?(%{wanted_since: %DateTime{} = since}, patience_hours, %DateTime{} = now)
      when is_integer(patience_hours) do
    DateTime.before?(now, DateTime.add(since, patience_hours * @hour))
  end

  @doc "The re-search interval in seconds for a want of the given age."
  @spec interval_seconds(non_neg_integer()) :: pos_integer()
  def interval_seconds(age_seconds) when age_seconds < 48 * @hour, do: 30 * 60
  def interval_seconds(age_seconds) when age_seconds < 7 * @day, do: 4 * @hour
  def interval_seconds(age_seconds) when age_seconds < 30 * @day, do: @day
  def interval_seconds(_age_seconds), do: 7 * @day

  defp interval_elapsed?(want, now) do
    age = DateTime.diff(now, want.wanted_since)
    next_due = DateTime.add(want.last_searched_at, interval_seconds(age))
    not DateTime.before?(now, next_due)
  end

  # The window lapsed between the last search and now — the floor
  # dropped, so the last search's negative knowledge is stale.
  defp patience_expired_since_last_search?(_want, 0, _now), do: false

  defp patience_expired_since_last_search?(want, patience_hours, now) do
    expiry = DateTime.add(want.wanted_since, patience_hours * @hour)
    DateTime.before?(want.last_searched_at, expiry) and not DateTime.before?(now, expiry)
  end
end
