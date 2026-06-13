defmodule MediaCentaurWeb.Components.Upcoming.MonthGrid do
  @moduledoc """
  Pure calendar-grid math for the mini-month companion. Produces the weeks of a
  month as rows of seven cells (a `Date` or `nil` padding), Monday-first, so the
  component is a thin renderer (ADR-030).
  """

  @doc "The month laid out as a list of 7-cell weeks (Monday-first; `nil` pads the edges)."
  @spec weeks(integer(), integer()) :: [[Date.t() | nil]]
  def weeks(year, month) do
    first = Date.new!(year, month, 1)
    leading = Date.day_of_week(first) - 1
    days = Enum.map(1..Date.days_in_month(first), &Date.new!(year, month, &1))

    Enum.chunk_every(List.duplicate(nil, leading) ++ days, 7, 7, List.duplicate(nil, 7))
  end
end
