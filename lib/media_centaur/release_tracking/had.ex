defmodule MediaCentaur.ReleaseTracking.Had do
  @moduledoc """
  Pure. Whether a release is **had** — the person needs nothing done
  about it — in the one reading every reader uses (campaign
  `discovery.md`, M16): the want ledger (`Wants`), the calendar's
  `Calendar.read/3` behind the Watchlist page and Discovery's Out Now,
  and the forecast (`UpcomingFeed`).

  Two halves, one answer. The library's half is derived: the linked
  container's last episode is the item's watermark
  (`last_library_season/episode`, written by `LibraryLinks`), and a
  release at or before it is flagged `in_library`. The person's half is
  authored: the caught-up point on their `Watchlist.TitleIntent`
  (`TitleIntent.caught_up/1`), the latest aired episode they have seen
  wherever they saw it. `point/2` is the later of the two; `had?/2` is
  `in_library`, or a series release at or before the point. A movie is
  had only when the library holds it — it has no position to be at.
  """

  alias MediaCentaur.ReleaseTracking.Item
  alias MediaCentaur.Watchlist.TitleIntent

  @typedoc "A season and episode pair; `{0, 0}` is no position at all."
  @type point :: {non_neg_integer(), non_neg_integer()}

  @doc "The later of the item's library watermark and the intent's caught-up point."
  @spec point(Item.t(), TitleIntent.caught_up() | nil) :: point()
  def point(%Item{} = item, caught_up) do
    watermark = {item.last_library_season || 0, item.last_library_episode || 0}

    case caught_up do
      nil -> watermark
      {_season, _episode} = pair -> max(watermark, pair)
    end
  end

  @doc """
  Whether nothing needs doing about `release`: it is in the library, or
  it is a series episode at or before `point`.
  """
  @spec had?(map(), point()) :: boolean()
  def had?(%{in_library: true}, _point), do: true

  def had?(%{season_number: season, episode_number: episode}, point)
      when is_integer(season) and is_integer(episode), do: {season, episode} <= point

  def had?(_release, _point), do: false
end
