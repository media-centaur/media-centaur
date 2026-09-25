defmodule MediaCentaurWeb.DiscoveryLive.People do
  @moduledoc """
  Folds the page's enriched activity rows into `Person` cards (ADR-030,
  UIDR-046): You first when an identity exists, then friends by their
  latest act of any kind, then friends with no acts by name. A former
  friend's activities (no nickname, not own) belong to nobody on the
  roster and get no card.

  A person's acts are one per title, newest first; each flies every act
  on that title in mast order, and a flag is **gold** when two or more
  friends on the roster did that act on that title — counted once over
  the rows this fold already holds, one count per friend per title and
  flag, the reader's own acts not counting. `rail/1` is the Feed's
  rail: the first eight of that order and how many the cap hid.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Friend
  alias MediaCentaurWeb.Components.Discovery.Person
  alias MediaCentaurWeb.Components.Discovery.Person.Act
  alias MediaCentaurWeb.Components.Discovery.Person.Entry
  alias MediaCentaurWeb.Components.Title.Flag

  @grade 2
  @rail_cap 8

  @doc """
  The cards for `friends` and, with `me: true`, for this identity, from
  the enriched activity rows. `now` anchors each act's relative time.
  """
  @spec build([map()], [Friend.t()], me: boolean(), now: DateTime.t()) :: [Person.t()]
  def build(rows, friends, opts) do
    now = Keyword.fetch!(opts, :now)
    by_author = Enum.group_by(rows, & &1.activity.author_pubkey)
    {own, theirs} = Enum.split_with(rows, & &1.own?)
    gold = gold_flags(theirs, friends)

    you = if Keyword.fetch!(opts, :me), do: [person("You", nil, nil, own, now, gold)], else: []

    friends
    |> Enum.map(fn friend ->
      person(
        friend.nickname,
        friend.pubkey,
        friend.inserted_at,
        Map.get(by_author, friend.pubkey, []),
        now,
        gold
      )
    end)
    |> Enum.sort_by(&sort_key/1)
    |> then(&(you ++ &1))
  end

  @doc "The Feed's rail: the first eight cards in `build/3`'s order, and how many the cap hid."
  @spec rail([Person.t()]) :: %{people: [Person.t()], hidden: non_neg_integer()}
  def rail(people) do
    {shown, hidden} = Enum.split(people, @rail_cap)
    %{people: shown, hidden: length(hidden)}
  end

  # The (title, flag) pairs at the grade: friends on the roster only,
  # each friend once per pair however many rows they have on it.
  defp gold_flags(rows, friends) do
    roster = MapSet.new(friends, & &1.pubkey)

    rows
    |> Enum.filter(&MapSet.member?(roster, &1.activity.author_pubkey))
    |> Enum.map(&{ref(&1), Flag.flag(&1.activity), &1.activity.author_pubkey})
    |> Enum.uniq()
    |> Enum.frequencies_by(fn {ref, flag, _author} -> {ref, flag} end)
    |> Enum.filter(fn {_pair, count} -> count >= @grade end)
    |> MapSet.new(fn {pair, _count} -> pair end)
  end

  # Latest act first; the quiet ones after, by name.
  defp sort_key(%Person{acts: [], name: name}), do: {1, 0, name}

  defp sort_key(%Person{acts: [%Act{acted_at: at} | _rest], name: name}),
    do: {0, -DateTime.to_unix(at), name}

  defp person(name, pubkey, added_at, rows, now, gold) do
    sorted = Enum.sort_by(rows, & &1.activity.acted_at, {:desc, DateTime})

    %Person{
      id: if(pubkey, do: "person-" <> String.slice(pubkey, 0, 8), else: "person-you"),
      name: name,
      own?: is_nil(pubkey),
      pubkey: pubkey,
      short_npub: pubkey && short_npub(pubkey),
      added_on: added_at && DateTime.to_date(added_at),
      acts: acts(sorted, gold, now)
    }
  end

  # One act per title in the order the titles first appear — newest
  # first, since the rows are sorted — with every row behind it.
  defp acts(sorted, gold, now) do
    by_ref = Enum.group_by(sorted, &ref/1)

    sorted
    |> Enum.map(&ref/1)
    |> Enum.uniq()
    |> Enum.map(&act(&1, Map.fetch!(by_ref, &1), gold, now))
  end

  defp act(ref, [%{activity: %Activity{} = newest} = first | _rest] = rows, gold, now) do
    flags = rows |> Enum.map(&Flag.flag(&1.activity)) |> Flag.sort_by_mast()

    %Act{
      ref: ref,
      title: newest.title,
      poster_url: first.poster_url,
      activity_id: newest.id,
      acted_at: newest.acted_at,
      ago: Format.relative_ago(newest.acted_at, now: now, sub_minute: :just_now),
      episode: newest.episode,
      flags: flags,
      gold: Enum.filter(flags, &MapSet.member?(gold, {ref, &1})),
      entries: Enum.map(rows, &entry/1)
    }
  end

  defp entry(%{activity: %Activity{} = activity}) do
    %Entry{
      activity_id: activity.id,
      kind: activity.kind,
      flag: Flag.flag(activity),
      episode: activity.episode,
      acted_at: activity.acted_at
    }
  end

  defp ref(%{activity: %Activity{tmdb_id: tmdb_id, media_type: media_type}}), do: {tmdb_id, media_type}

  @doc "The npub, elided in the middle — enough to compare against what a friend told you."
  @spec short_npub(String.t()) :: String.t()
  def short_npub(pubkey) do
    npub = Social.to_npub(pubkey)
    String.slice(npub, 0, 9) <> "…" <> String.slice(npub, -4..-1//1)
  end
end
