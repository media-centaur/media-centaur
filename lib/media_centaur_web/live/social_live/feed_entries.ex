defmodule MediaCentaurWeb.SocialLive.FeedEntries do
  @moduledoc """
  The Feed's rows from the page's enriched activity rows (ADR-030,
  UIDR-038, UIDR-045): every author's reviews and listings — friends'
  and this identity's own — one row per action, newest first, flat.
  Nothing groups and nothing re-sorts. Watched actions and any title at
  the Ignored rung make no row for any author; a former friend's rows
  never reach the page (Activities lists rows for known people only).

  The scope filters by author after the entry rule: `:everyone`,
  `:friends` (no own rows) or `:you` (own rows only). It is navigation
  state — the page reads it off `?scope=` with `parse_scope/1` and
  writes it back with `scope_query/1`, the one pair that spells the
  scope in a URL — never a preference.

  Paging is a window with a cap and a queued head (UIDR-046). The
  window is the newest `window` rows — twenty at first, *Show older*
  adding twenty (`page_size/0`) to the cap of sixty (`cap/0`);
  `has_older?` says whether *Show older* has anything to show and
  `at_cap?` that the cap hides older actions. The `head` is the newest
  band the reader was shown: `nil` while the column's top is in view,
  so an arrival prepends live; else that activity's id, which freezes
  the window there and counts what sorts above it as `queued` — "N
  new" until pressed. A head the list no longer holds is live again.
  The tab's count is the window's size under the current scope.

  `empty_reason/3` is the empty state's diagnosis (UIDR-034), given
  whether a relay exists and how many people the reader follows and
  shows: the You scope needs no relay and no friend, since a review
  creates its row locally; the other scopes ask for a relay first —
  Social is on by default, so a person who never opted in reads why
  nothing arrives and where the switch is — then for a followed person.

  Every row's toolbar is its title's `ToolbarSlots`. The Feed's one
  glyph is the review's sentiment at its grade — the host hands
  `grades:` (`Title.Grade.grades/1` over the page's rows) so the count
  is the one the cards draw.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.ToolbarSlots
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.Grade
  alias MediaCentaurWeb.SocialLive.ActivityWords

  @page_size 20
  @cap 60
  @kinds [:review, :listing]

  @type scope :: :everyone | :friends | :you
  @type empty_reason :: :no_relay | :no_friends | :quiet | :nothing_shared

  @doc "Rows per window — the initial load and each Show older step."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @doc "The most rows a window shows; past it the foot says so."
  @spec cap() :: pos_integer()
  def cap, do: @cap

  @doc "The scope named by the URL's `scope` param; Everyone for anything else."
  @spec parse_scope(String.t() | nil) :: scope()
  def parse_scope("friends"), do: :friends
  def parse_scope("you"), do: :you
  def parse_scope(_other), do: :everyone

  @doc "The query that names `scope` in a URL — `parse_scope/1`'s inverse. Everyone is the bare address."
  @spec scope_query(scope()) :: keyword()
  def scope_query(:everyone), do: []
  def scope_query(scope), do: [scope: Atom.to_string(scope)]

  @doc "Why the feed is empty under `scope`, given whether a relay exists and how many friends there are."
  @spec empty_reason(scope(), boolean(), non_neg_integer()) :: empty_reason()
  def empty_reason(:you, _relay?, _friend_count), do: :nothing_shared
  def empty_reason(_scope, false, _friend_count), do: :no_relay
  def empty_reason(_scope, true, 0), do: :no_friends
  def empty_reason(_scope, true, _friend_count), do: :quiet

  @doc """
  The windowed rows under `scope`, newest first, at or below the `head`.
  `now` anchors each row's relative time; a `window` past the cap is the
  cap.
  """
  @spec build([map()],
          now: DateTime.t(),
          window: pos_integer(),
          scope: scope(),
          head: String.t() | nil,
          grades: %{{Grade.ref(), Flag.flag()} => Grade.t()}
        ) ::
          %{
            entries: [FeedEntry.t()],
            has_older?: boolean(),
            at_cap?: boolean(),
            queued: non_neg_integer()
          }
  def build(rows, opts) do
    now = Keyword.fetch!(opts, :now)
    window = min(Keyword.fetch!(opts, :window), @cap)
    scope = Keyword.fetch!(opts, :scope)
    grades = Keyword.fetch!(opts, :grades)

    sorted =
      rows
      |> Enum.filter(&(entry?(&1) and in_scope?(&1, scope)))
      |> Enum.sort_by(& &1.activity.acted_at, {:desc, DateTime})

    {queued, visible} = split_at_head(sorted, Keyword.get(opts, :head))

    %{
      entries: visible |> Enum.take(window) |> Enum.map(&entry(&1, now, grades)),
      has_older?: length(visible) > window and window < @cap,
      at_cap?: window == @cap and length(visible) > @cap,
      queued: length(queued)
    }
  end

  # The head is the newest band the reader was shown; what sorts above it
  # arrived since and waits behind "N new". No head, or a head that was
  # withdrawn, is live.
  defp split_at_head(sorted, nil), do: {[], sorted}

  defp split_at_head(sorted, head) do
    case Enum.split_while(sorted, &(&1.activity.id != head)) do
      {_all, []} -> {[], sorted}
      {above, from_head} -> {above, from_head}
    end
  end

  # The entry rule: a review or a listing on a title not ignored. Who
  # wrote it is the scope's question; that the author is known is
  # Activities' (a former friend's rows never reach the page).
  defp entry?(%{activity: activity, rung: rung}), do: activity.kind in @kinds and rung != :ignored

  defp in_scope?(_row, :everyone), do: true
  defp in_scope?(%{author: %Person{own?: own?}}, :friends), do: not own?
  defp in_scope?(%{author: %Person{own?: own?}}, :you), do: own?

  defp entry(%{activity: activity} = row, now, grades) do
    ref = {activity.tmdb_id, activity.media_type}

    %FeedEntry{
      id: "feed-row-" <> activity.id,
      activity_id: activity.id,
      ref: ref,
      title: activity.title,
      poster_url: row.poster_url,
      author: row.author,
      subject: ActivityWords.subject(row.author),
      kind: activity.kind,
      episode: nil,
      glyphs: glyphs(activity, ref, grades),
      text: if(activity.kind == :review, do: activity.text),
      acted_at: activity.acted_at,
      ago: Format.relative_ago(activity.acted_at, now: now, sub_minute: :just_now),
      slots: ToolbarSlots.resolve(row)
    }
  end

  # The Feed's one glyph: the review's sentiment at its grade; none for
  # a review without one or a listing (UIDR-046).
  defp glyphs(%Activity{kind: :review, sentiment: sentiment}, ref, grades) when not is_nil(sentiment),
    do: [{sentiment, Map.fetch!(grades, {ref, sentiment})}]

  defp glyphs(_activity, _ref, _grades), do: []
end
