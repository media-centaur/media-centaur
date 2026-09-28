defmodule MediaCentaurWeb.DiscoveryLive.People do
  @moduledoc """
  Folds the page's enriched activity rows into person cards (ADR-030,
  ADR-074, UIDR-046): one `Card` — a `Social.Person` and their acts —
  for the reader first when the known people include them, then friends
  by their latest act of any kind, then friends with no acts by name.
  The rows carry known people only (Activities drops a former friend's),
  so every row lands on a card.

  A person's acts are one per title, newest first; each flies every act
  on that title in mast order, each at its grade (`Grade`: by how many
  people flew that flag on that title) — counted once over the rows this
  fold already holds, one count per person per title and flag, the
  reader included. `rail/1` is the Feed's rail: the first
  eight of that order and how many the cap hid.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Discovery.Act
  alias MediaCentaurWeb.Components.Discovery.Act.Entry
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.Grade

  defmodule Card do
    @moduledoc """
    One person card's content: the person as the reader sees them and
    their acts, newest first. `PersonCard` renders it from the two
    attrs; `PersonCard.dom_id/1` names it.
    """

    @enforce_keys [:person]
    defstruct [:person, acts: []]

    @type t :: %__MODULE__{person: Person.t(), acts: [Act.t()]}
  end

  @rail_cap 8

  @doc """
  The cards for `people` (the `Social.people/0` map) from the enriched
  activity rows. `now` anchors each act's relative time.
  """
  @spec build([map()], %{optional(String.t()) => Person.t()}, now: DateTime.t()) :: [Card.t()]
  def build(rows, people, opts) do
    now = Keyword.fetch!(opts, :now)
    by_author = Enum.group_by(rows, & &1.activity.author_pubkey)
    grades = Grade.grades(rows)
    {me, friends} = people |> Map.values() |> Enum.split_with(& &1.own?)

    you = Enum.map(me, &card(&1, Map.get(by_author, &1.pubkey, []), now, grades))

    friends
    |> Enum.map(&card(&1, Map.get(by_author, &1.pubkey, []), now, grades))
    |> Enum.sort_by(&sort_key/1)
    |> then(&(you ++ &1))
  end

  @doc "The Feed's rail: the first eight cards in `build/3`'s order, and how many the cap hid."
  @spec rail([Card.t()]) :: %{cards: [Card.t()], hidden: non_neg_integer()}
  def rail(cards) do
    {shown, hidden} = Enum.split(cards, @rail_cap)
    %{cards: shown, hidden: length(hidden)}
  end

  # Latest act first; the quiet ones after, by name.
  defp sort_key(%Card{acts: [], person: person}), do: {1, 0, Format.person_name(person)}

  defp sort_key(%Card{acts: [%Act{acted_at: at} | _rest], person: person}),
    do: {0, -DateTime.to_unix(at), Format.person_name(person)}

  defp card(%Person{} = person, rows, now, grades) do
    sorted = Enum.sort_by(rows, & &1.activity.acted_at, {:desc, DateTime})
    %Card{person: person, acts: acts(sorted, grades, now)}
  end

  # One act per title in the order the titles first appear — newest
  # first, since the rows are sorted — with every row behind it.
  defp acts(sorted, grades, now) do
    by_ref = Enum.group_by(sorted, &ref/1)

    sorted
    |> Enum.map(&ref/1)
    |> Enum.uniq()
    |> Enum.map(&act(&1, Map.fetch!(by_ref, &1), grades, now))
  end

  defp act(ref, [%{activity: %Activity{} = newest} = first | _rest] = rows, grades, now) do
    flags = rows |> Enum.map(&Flag.flag(&1.activity)) |> Flag.sort()

    %Act{
      ref: ref,
      title: newest.title,
      poster_url: first.poster_url,
      activity_id: newest.id,
      acted_at: newest.acted_at,
      ago: Format.relative_ago(newest.acted_at, now: now, sub_minute: :just_now),
      episode: newest.episode,
      flags: flags,
      grades: Map.new(flags, &{&1, Map.fetch!(grades, {ref, &1})}),
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
end
