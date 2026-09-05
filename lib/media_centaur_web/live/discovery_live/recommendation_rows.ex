defmodule MediaCentaurWeb.DiscoveryLive.RecommendationRows do
  @moduledoc """
  The Recommendations tab's rows from the page's enriched activity rows
  (ADR-030, UIDR-031): friends' recommendations only, one row per title,
  placed by its newest recommendation. The lead names every recommender
  newest first with the newest time ("Cleo, Bob · 1h ago"); a lone
  recommender's note is plain, several recommenders' notes are
  attributed. The row's joins (poster, library owner, watchlist,
  acquisition state) are the title's, taken from any row that carried
  them — every activity row for a title carries the same.
  """

  alias MediaCentaur.Format

  @type row :: %{
          ref: {integer(), MediaCentaur.TMDB.Title.media_type()},
          title: MediaCentaur.TMDB.Title.t(),
          poster_url: String.t() | nil,
          library_owner_id: term() | nil,
          on_watchlist?: boolean(),
          acquisition_state: atom() | nil,
          activities: [map()],
          newest: map(),
          lead: String.t(),
          notes: [%{name: String.t() | nil, text: String.t()}]
        }

  @doc "The rows, newest recommendation first. `now` anchors the lead's relative time."
  @spec build([map()], now: DateTime.t()) :: [row()]
  def build(rows, opts) do
    now = Keyword.fetch!(opts, :now)

    rows
    |> Enum.filter(&(&1.activity.kind == :recommendation and not &1.own? and &1.nickname != nil))
    |> Enum.group_by(&{&1.activity.tmdb_id, &1.activity.media_type})
    |> Enum.map(fn {ref, group} -> row(ref, group, now) end)
    |> Enum.sort_by(& &1.newest.activity.acted_at, {:desc, DateTime})
  end

  defp row(ref, group, now) do
    activities = Enum.sort_by(group, & &1.activity.acted_at, {:desc, DateTime})
    newest = hd(activities)

    %{
      ref: ref,
      title: newest.activity.title,
      poster_url: newest.poster_url,
      library_owner_id: newest.library_owner_id,
      on_watchlist?: newest.on_watchlist?,
      acquisition_state: newest.acquisition_state,
      activities: activities,
      newest: newest,
      lead:
        Enum.map_join(activities, ", ", & &1.nickname) <>
          " · " <> Format.relative_ago(newest.activity.acted_at, now: now),
      notes: notes(activities)
    }
  end

  defp notes([%{activity: %{note: nil}}]), do: []
  defp notes([%{activity: %{note: note}}]), do: [%{name: nil, text: note}]

  defp notes(activities) do
    for %{activity: %{note: note}, nickname: name} <- activities,
        note != nil,
        do: %{name: name, text: note}
  end
end
