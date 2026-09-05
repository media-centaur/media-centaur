defmodule MediaCentaur.Acquisition.Plans.DownloadScope do
  @moduledoc """
  What a one-click download of a series covers (spec 2026-09-05 §8–9),
  as `{season, episode}` units over a `Targeting.Selection`:

  * `:first_season` — the lowest season numbered 1 or higher that has at
    least one pickable episode (aired, not in the library, not tracked),
    and exactly those episodes of that season. Specials (season 0) are
    never part of it.
  * `:everything` — the picker's default (`Targeting.default_units/1`):
    every pickable episode, specials included.

  Pure; the caller (`Plans.plan_title/2`) owns the TMDB fetch, the plan
  creation and, for `:everything`, the tracking hand-off.
  """

  alias MediaCentaur.Acquisition.Targeting

  @type scope :: :first_season | :everything

  @spec units(Targeting.Selection.t(), scope()) :: [{pos_integer(), pos_integer()}]
  def units(%Targeting.Selection{} = selection, :everything), do: Targeting.default_units(selection)

  def units(%Targeting.Selection{} = selection, :first_season) do
    selection
    |> Targeting.default_units()
    |> Enum.reject(fn {season, _episode} -> season < 1 end)
    |> Enum.group_by(fn {season, _episode} -> season end)
    |> Enum.min_by(fn {season, _units} -> season end, fn -> {nil, []} end)
    |> elem(1)
  end
end
