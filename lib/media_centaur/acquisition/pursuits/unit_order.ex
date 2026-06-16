defmodule MediaCentaur.Acquisition.Pursuits.UnitOrder do
  @moduledoc """
  Derives stable `position` values for a composite pursuit's units from
  season/episode order.

  A pursuit's units carry `season_number`/`episode_number`
  ([ADR-055](../../../../decisions/architecture/2026-06-09-055-composite-pursuits.md)),
  but are otherwise created in insertion order (brace-expansion / pick
  order). Because unit queries and the residual-driven descent
  (`Jobs.RunPlan`) walk units by `position`, deriving `position` from
  airing order makes searches/grabs proceed season → episode rather
  than in whichever order the user happened to pick.

  The sort is **stable** and degrades cleanly: a unit whose season or
  episode is `nil` (a movie, an unparseable query term) sorts after
  numbered units while keeping its relative input order, and a pursuit
  whose units *all* lack season/episode is returned unchanged. So
  wiring this into a creation path never reorders the cases it can't
  rank.
  """

  # nil season/episode sorts after any real number while leaving
  # equal-key items in input order (Enum.sort_by/3 is stable).
  @sentinel 1_000_000

  @doc """
  Stable-sorts `items` into airing order and pairs each with its
  zero-based `position`.

  `key_fun` extracts `{season_number, episode_number}` from an item;
  either element may be `nil`. Returns `[{item, position}]` in sorted
  order.
  """
  @spec with_positions([item], (item -> {integer() | nil, integer() | nil})) ::
          [{item, non_neg_integer()}]
        when item: term()
  def with_positions(items, key_fun) when is_function(key_fun, 1) do
    items
    |> Enum.sort_by(fn item -> sort_key(key_fun.(item)) end, :asc)
    |> Enum.with_index()
  end

  defp sort_key({season, episode}), do: {season || @sentinel, episode || @sentinel}
end
