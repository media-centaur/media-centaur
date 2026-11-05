defmodule MediaCentaur.Acquisition.Plans.DownloadScope do
  @moduledoc """
  What a one-click download of a series covers (spec 2026-09-05 §8–9),
  as `{season, episode}` units over a `Targeting.Selection`. Every rule
  starts from the pickable episodes (`Targeting.default_units/1`: aired,
  not in the library, not tracked):

  * `:first_missing_season` — the lowest season numbered 1 or higher
    that has at least one pickable episode, and exactly those episodes
    of that season.
  * `:everything` — the picker's default: every pickable episode,
    specials included.
  * `:latest_season` — the highest season numbered 1 or higher that has
    aired an episode, and its pickable episodes; nothing when that
    season is already had. It never falls back to an older season.

  Specials (season 0) are never part of a season rule. `scopes/0` is
  the closed set in menu order and `parse/1` its wire form; the picker's
  presets of the same names read `units/2` (`DownloadsLive.PlanLogic`).

  The scope select on the title detail offers a fourth value, *Choose
  episodes* (`Title.ModalState.scope_choice/0`), which is not a scope: it
  resolves to no units here, because the picker on Downloads resolves them
  (spec 2026-09-23 §1).

  Pure; the caller (`Plans.create_title_plan/2`) owns the TMDB fetch and
  the plan creation. No scope follows the series (ADR-066): the title
  detail's *Grab new episodes as they air* switch is the person's own
  act beside the download.
  """

  alias MediaCentaur.Acquisition.Targeting

  @scopes [:first_missing_season, :everything, :latest_season]

  @type scope :: :first_missing_season | :everything | :latest_season

  @doc "Every scope, in the order the title detail's select offers them."
  @spec scopes() :: [scope()]
  def scopes, do: @scopes

  @doc "A scope from its wire form — a closed set, mapped explicitly."
  @spec parse(term()) :: {:ok, scope()} | :error
  def parse(value) when is_binary(value) do
    case Enum.find(@scopes, &(Atom.to_string(&1) == value)) do
      nil -> :error
      scope -> {:ok, scope}
    end
  end

  def parse(_value), do: :error

  @spec units(Targeting.Selection.t(), scope()) :: [{pos_integer(), pos_integer()}]
  def units(%Targeting.Selection{} = selection, :everything), do: Targeting.default_units(selection)

  def units(%Targeting.Selection{} = selection, :first_missing_season) do
    selection
    |> Targeting.default_units()
    |> Enum.reject(fn {season, _episode} -> season < 1 end)
    |> Enum.group_by(fn {season, _episode} -> season end)
    |> Enum.min_by(fn {season, _units} -> season end, fn -> {nil, []} end)
    |> elem(1)
  end

  def units(%Targeting.Selection{} = selection, :latest_season) do
    case latest_aired_season(selection) do
      nil -> []
      latest -> selection |> Targeting.default_units() |> Enum.filter(&(elem(&1, 0) == latest))
    end
  end

  defp latest_aired_season(%Targeting.Selection{seasons: seasons}) do
    seasons
    |> Enum.filter(&(&1.season_number >= 1 and Enum.any?(&1.episodes, fn episode -> episode.aired? end)))
    |> Enum.map(& &1.season_number)
    |> Enum.max(fn -> nil end)
  end
end
