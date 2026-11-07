defmodule MediaCentaurWeb.HeroRotation do
  @moduledoc """
  Which of a page's hero candidates is showing right now: one pick per
  seven-hour block of the clock, the same function for Home (over the
  library's hero candidates) and Discovery (over the New Releases shelf's
  first members). Pure: the pick changes when a page re-assigns its hero,
  on mount or when its candidates change, never on a timer.
  """

  @rotation_hours 7

  @doc """
  Picks one candidate from `candidates` deterministically based on `now`.
  Rotation interval is #{@rotation_hours} hours: every #{@rotation_hours}-hour
  block of UTC unix time selects the next candidate. The interval is
  deliberately coprime with 24 — a habitual viewer who only opens the
  app at the same time each day still cycles through the full pool over
  ~#{Float.round(@rotation_hours * 12 / 24, 1)} days for a 12-candidate
  pool. Picking a divisor of 24 (4/6/8/12 h) would lock such a viewer
  into a single time-of-day slot and reduce variety.

  Returns `nil` for an empty list.
  """
  @spec select([term()], DateTime.t()) :: term() | nil
  def select(candidates, now \\ DateTime.utc_now())
  def select([], _now), do: nil

  def select(candidates, %DateTime{} = now), do: candidates |> rotate(now) |> List.first()

  @doc """
  `candidates` in rotation order for `now`: the current pick first, then
  the candidates after it, wrapping around. A page that must pass over
  some candidates takes the first one it accepts, so a skipped pick hands
  its block to the next candidate and every other block keeps its pick.
  """
  @spec rotate([term()], DateTime.t()) :: [term()]
  def rotate(candidates, now \\ DateTime.utc_now())
  def rotate([], _now), do: []

  def rotate(candidates, %DateTime{} = now) do
    blocks = div(DateTime.to_unix(now), @rotation_hours * 3600)
    {before, from_pick} = Enum.split(candidates, rem(blocks, length(candidates)))
    from_pick ++ before
  end
end
