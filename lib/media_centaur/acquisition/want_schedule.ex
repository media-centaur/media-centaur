defmodule MediaCentaur.Acquisition.WantSchedule do
  @moduledoc """
  Pure re-search scheduling for release-tracking wants (ADR-056 Q6):
  the stepped back-off that decides whether a want is *search-due* at a
  tick.

  The schedule follows availability reality — releases appear within
  hours-to-days of airing, so the hot window is aggressive; after a
  week unfound the cadence backs off, but it **never gives up**:
  stopping is a user dismissal, not a timeout.

      want age          re-search interval
      0–48 h            30 min   (the corpus freshness window)
      48 h – 7 d        4 h
      7 – 30 d          24 h
      30 d +            7 d, forever

  There is no patience window (UIDR-041 §6): every search takes the
  best release available at the automatic floor, so nothing about a
  want's age changes what it will accept, only how often it looks.
  """

  @hour 3600
  @day 24 * @hour

  @doc """
  Whether the want should be searched at `now`. Never-searched wants
  are due immediately; otherwise the age-band interval applies.
  """
  @spec due?(struct(), DateTime.t()) :: boolean()
  def due?(%{last_searched_at: nil}, _now), do: true
  def due?(want, %DateTime{} = now), do: interval_elapsed?(want, now)

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
end
