defmodule MediaCentaurWeb.DiscoveryLive.People do
  @moduledoc """
  Folds the page's enriched activity rows into the Friends tab's
  `Person` cards (ADR-030, UIDR-031): You first when an identity exists,
  then friends by their latest activity, then friends with nothing
  shared by name. A former friend's activities (no nickname, not own)
  belong to nobody on the roster and get no card.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Friend
  alias MediaCentaurWeb.Components.Discovery.Person
  alias MediaCentaurWeb.Components.Discovery.Person.Entry
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords

  @doc """
  The cards for `friends` and, with `me: true`, for this identity, from
  the enriched activity rows. `now` anchors the presence line's
  relative time.
  """
  @spec build([map()], [Friend.t()], me: boolean(), now: DateTime.t()) :: [Person.t()]
  def build(rows, friends, opts) do
    now = Keyword.fetch!(opts, :now)
    by_author = Enum.group_by(rows, & &1.activity.author_pubkey)
    {own, _theirs} = Enum.split_with(rows, & &1.own?)

    you = if Keyword.fetch!(opts, :me), do: [person("You", nil, nil, own, now)], else: []

    friends
    |> Enum.map(fn friend ->
      person(
        friend.nickname,
        friend.pubkey,
        friend.inserted_at,
        Map.get(by_author, friend.pubkey, []),
        now
      )
    end)
    |> Enum.sort_by(&sort_key/1)
    |> then(&(you ++ &1))
  end

  # Latest activity first; the quiet ones after, by name.
  defp sort_key(%Person{presence: nil, name: name}), do: {1, 0, name}
  defp sort_key(%Person{presence: %{at: at}, name: name}), do: {0, -DateTime.to_unix(at), name}

  defp person(name, pubkey, added_at, rows, now) do
    sorted = Enum.sort_by(rows, & &1.activity.acted_at, {:desc, DateTime})
    shelves = Enum.group_by(sorted, & &1.activity.kind, &entry/1)

    %Person{
      id: if(pubkey, do: "person-" <> String.slice(pubkey, 0, 8), else: "person-you"),
      name: name,
      own?: is_nil(pubkey),
      pubkey: pubkey,
      short_npub: pubkey && short_npub(pubkey),
      added_on: added_at && DateTime.to_date(added_at),
      presence: presence(List.first(sorted), now),
      watched: Map.get(shelves, :watched, []),
      tracking: Map.get(shelves, :tracking, []),
      recommended: Map.get(shelves, :recommendation, [])
    }
  end

  defp entry(%{activity: %Activity{} = activity} = row) do
    %Entry{
      activity_id: activity.id,
      ref: {activity.tmdb_id, activity.media_type},
      title: activity.title,
      poster_url: row.poster_url,
      sentiment: if(activity.kind == :recommendation, do: activity.sentiment),
      episode: activity.episode,
      acted_at: activity.acted_at
    }
  end

  defp presence(nil, _now), do: nil

  defp presence(%{activity: %Activity{} = activity}, now) do
    %{
      text: ActivityWords.presence(activity.kind, activity.episode, activity.title.name),
      ago: Format.relative_ago(activity.acted_at, now: now),
      at: activity.acted_at
    }
  end

  @doc "The npub, elided in the middle — enough to compare against what a friend told you."
  @spec short_npub(String.t()) :: String.t()
  def short_npub(pubkey) do
    npub = Social.to_npub(pubkey)
    String.slice(npub, 0, 9) <> "…" <> String.slice(npub, -4..-1//1)
  end
end
