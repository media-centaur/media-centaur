defmodule MediaCentaurWeb.DiscoveryLive.FeedEntries do
  @moduledoc """
  The Feed's rows from the page's enriched activity rows (ADR-030,
  UIDR-038, UIDR-045): every author's reviews and listings — friends'
  and this identity's own — one row per action, newest first, flat.
  Nothing groups and nothing re-sorts. Watched actions, a former
  friend's actions and any title at the Ignored rung make no row for
  any author; the activities themselves stay for the Friends tab and
  the pennants.

  The scope filters by author after the entry rule: `:everyone`,
  `:friends` (no own rows) or `:you` (own rows only). It is navigation
  state — the page reads it off `?scope=` with `parse_scope/1` and
  writes it back with `scope_query/1`, the one pair that spells the
  scope in a URL — never a preference. The window is the newest `window` rows; `has_older?`
  says whether *Show older* has anything to show. The tab's count is
  the window's size under the current scope.

  `empty_reason/2` is the empty state's diagnosis (UIDR-034): the You
  scope needs no relay and no friend, since a review creates its row
  locally; the other scopes ask whether the network is ready first.

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

  @type scope :: :everyone | :friends | :you
  @type empty_reason :: :not_ready | :quiet | :nothing_shared

  @doc "Rows per window — the initial load and each Show older step."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @doc "The scope named by the URL's `scope` param; Everyone for anything else."
  @spec parse_scope(String.t() | nil) :: scope()
  def parse_scope("friends"), do: :friends
  def parse_scope("you"), do: :you
  def parse_scope(_other), do: :everyone

  @doc "The query that names `scope` in a URL — `parse_scope/1`'s inverse. Everyone is the bare address."
  @spec scope_query(scope()) :: keyword()
  def scope_query(:everyone), do: []
  def scope_query(scope), do: [scope: Atom.to_string(scope)]

  @doc "Why the feed is empty under `scope`, given whether a relay and a friend exist."
  @spec empty_reason(scope(), boolean()) :: empty_reason()
  def empty_reason(:you, _ready?), do: :nothing_shared
  def empty_reason(_scope, false), do: :not_ready
  def empty_reason(_scope, true), do: :quiet

  @doc "The windowed rows under `scope`, newest first. `now` anchors each row's relative time."
  @spec build([map()], now: DateTime.t(), window: pos_integer(), scope: scope()) ::
          %{entries: [FeedEntry.t()], has_older?: boolean()}
  def build(rows, opts) do
    now = Keyword.fetch!(opts, :now)
    window = Keyword.fetch!(opts, :window)
    scope = Keyword.fetch!(opts, :scope)

    entries =
      rows
      |> Enum.filter(&(entry?(&1) and in_scope?(&1, scope)))
      |> Enum.sort_by(& &1.activity.acted_at, {:desc, DateTime})

    %{
      entries: entries |> Enum.take(window) |> Enum.map(&entry(&1, now)),
      has_older?: length(entries) > window
    }
  end

  # The entry rule: a review or a listing, by an author on the roster or
  # by this identity, on a title not ignored. Who wrote it is the scope's
  # question, not this one's.
  defp entry?(%{activity: activity, own?: own?, nickname: nickname, rung: rung}),
    do: activity.kind in @kinds and (own? or nickname != nil) and rung != :ignored

  defp in_scope?(_row, :everyone), do: true
  defp in_scope?(%{own?: own?}, :friends), do: not own?
  defp in_scope?(%{own?: own?}, :you), do: own?

  defp entry(%{activity: activity} = row, now) do
    %FeedEntry{
      id: "feed-row-" <> activity.id,
      activity_id: activity.id,
      ref: {activity.tmdb_id, activity.media_type},
      title: activity.title,
      poster_url: row.poster_url,
      author: if(row.own?, do: "You", else: row.nickname),
      own?: row.own?,
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
