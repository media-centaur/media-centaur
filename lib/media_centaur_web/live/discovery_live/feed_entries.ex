defmodule MediaCentaurWeb.DiscoveryLive.FeedEntries do
  @moduledoc """
  The Feed's entries from the page's enriched activity rows (ADR-030,
  UIDR-038): friends' reviews and listings, one entry per
  action, newest first, flat. Nothing groups and nothing re-sorts — two
  friends on one title are two entries, and one friend reviewing then
  listing a title is two adjacent entries. Watched actions, own actions,
  a former friend's actions and any title at the Ignored rung make no
  entry; the activities themselves stay for the Friends tab and the
  pennants.

  The window is the newest `window` entries; `has_older?` says whether
  *Show older* has anything to show. The tab's count is the window's
  size.

  The toolbar's two resolved slots come from the same three facts the
  row markers read — the rung, library presence, the acquisition state —
  with `Logic.acquisition_marker/1` supplying the acquisition words so
  no state is spelled twice.
  """

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Format
  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.Components.Title.Logic

  @page_size 50
  @kinds [:review, :listing]

  @doc "Entries per window — the initial load and each Show older step."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @doc "The windowed entries, newest first. `now` anchors each entry's relative time."
  @spec build([map()], now: DateTime.t(), window: pos_integer()) ::
          %{entries: [FeedEntry.t()], has_older?: boolean()}
  def build(rows, opts) do
    now = Keyword.fetch!(opts, :now)
    window = Keyword.fetch!(opts, :window)

    entries =
      rows
      |> Enum.filter(&entry?/1)
      |> Enum.sort_by(& &1.activity.acted_at, {:desc, DateTime})

    %{
      entries: entries |> Enum.take(window) |> Enum.map(&entry(&1, now)),
      has_older?: length(entries) > window
    }
  end

  defp entry?(%{activity: activity, own?: own?, nickname: nickname, rung: rung}),
    do: activity.kind in @kinds and not own? and nickname != nil and rung != :ignored

  defp entry(%{activity: activity} = row, now) do
    %FeedEntry{
      id: "feed-entry-" <> activity.id,
      activity_id: activity.id,
      ref: {activity.tmdb_id, activity.media_type},
      title: activity.title,
      poster_url: row.poster_url,
      nickname: row.nickname,
      kind: activity.kind,
      sentiment: if(activity.kind == :review, do: activity.sentiment),
      text: if(activity.kind == :review, do: activity.text),
      acted_at: activity.acted_at,
      ago: Format.relative_ago(activity.acted_at, now: now, sub_minute: :just_now),
      rung: row.rung,
      library_owner_id: row.library_owner_id,
      acquisition_state: row.acquisition_state,
      list_slot: list_slot(row),
      download_slot: download_slot(row)
    }
  end

  @doc "What the List position holds: the verb below the list, Listed on it, Following above it."
  @spec list_slot(%{rung: TitleIntent.rung() | nil}) :: FeedEntry.list_slot()
  def list_slot(%{rung: :list}), do: :listed

  def list_slot(%{rung: rung}) do
    if TitleIntent.follows_releases?(rung), do: :following, else: :list
  end

  @doc "What the Download position holds: In library, the acquisition marker while a plan runs, else the verb."
  @spec download_slot(%{library_owner_id: term() | nil, acquisition_state: atom() | nil}) ::
          FeedEntry.download_slot()
  def download_slot(%{library_owner_id: owner}) when not is_nil(owner), do: {:state, "In library"}

  def download_slot(%{acquisition_state: state}) do
    case Logic.acquisition_marker(state) do
      nil -> :download
      word -> {:state, word}
    end
  end
end
