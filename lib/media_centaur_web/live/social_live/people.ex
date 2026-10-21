defmodule MediaCentaurWeb.SocialLive.People do
  @moduledoc """
  Folds the page's enriched activity rows into person cards (ADR-030,
  ADR-074, UIDR-046): one `Card` — a `Social.Person` and their acts —
  for the reader first when the known people include them, then every
  followed person by their latest act of any kind, then those with no
  acts by name. The host hands `build/3` `Social.visible_people/0`, so
  it never meets a hidden person; the rows carry known people only
  (Activities drops a former friend's and a hidden person's), so every
  row lands on a card. `hidden/1` is the Friends tab's **hidden group**:
  the hidden people from `Social.people/0`, by name, each with Show.

  A person's acts are one row per title (`FeedEntry`, the person page's
  row: the newest act's verb, every flag on the title at its grade —
  `Grade`, one count per person per title and flag over the rows this
  fold holds, the reader included — the review's words, the title's
  toolbar slots), newest first; the person card's strip and the person
  page's list are both this fold. `rail/1` is the Feed's rail: the first
  eight of that order and how many the cap hid.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.ToolbarSlots
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.Grade
  alias MediaCentaurWeb.SocialLive.ActivityWords

  defmodule Card do
    @moduledoc """
    One person card's content: the person as the reader sees them and
    their acts, newest first — one `FeedEntry` per title acted on. `PersonCard` renders it from the two
    attrs; `PersonCard.dom_id/1` names it.
    """

    @enforce_keys [:person]
    defstruct [:person, acts: []]

    @type t :: %__MODULE__{person: Person.t(), acts: [FeedEntry.t()]}
  end

  @rail_cap 8

  @doc """
  The cards for `people` (the `Social.visible_people/0` map) from the
  enriched activity rows. `now` anchors each act's relative time;
  `grades:` is `Title.Grade.grades/1` over the same rows — the host
  computes it once for the cards and the Feed.
  """
  @spec build([map()], %{optional(String.t()) => Person.t()},
          now: DateTime.t(),
          grades: %{{Grade.ref(), Flag.flag()} => Grade.t()}
        ) :: [Card.t()]
  def build(rows, people, opts) do
    now = Keyword.fetch!(opts, :now)
    by_author = Enum.group_by(rows, & &1.activity.author_pubkey)
    grades = Keyword.fetch!(opts, :grades)
    {me, friends} = people |> Map.values() |> Enum.split_with(& &1.own?)

    you = Enum.map(me, &card(&1, Map.get(by_author, &1.pubkey, []), now, grades))

    friends
    |> Enum.map(&card(&1, Map.get(by_author, &1.pubkey, []), now, grades))
    |> Enum.sort_by(&sort_key/1)
    |> then(&(you ++ &1))
  end

  @doc "The hidden people, by name: the Friends tab's hidden group, which `build/3` leaves out."
  @spec hidden(%{optional(String.t()) => Person.t()}) :: [Person.t()]
  def hidden(people),
    do: people |> Map.values() |> Enum.filter(& &1.hidden) |> Enum.sort_by(&Format.person_name/1)

  @doc "The Feed's rail: the first eight cards in `build/3`'s order, and how many the cap hid."
  @spec rail([Card.t()]) :: %{cards: [Card.t()], hidden: non_neg_integer()}
  def rail(cards) do
    {shown, hidden} = Enum.split(cards, @rail_cap)
    %{cards: shown, hidden: length(hidden)}
  end

  # Latest act first; the quiet ones after, by name.
  defp sort_key(%Card{acts: [], person: person}), do: {1, 0, Format.person_name(person)}

  defp sort_key(%Card{acts: [%FeedEntry{acted_at: at} | _rest], person: person}),
    do: {0, -DateTime.to_unix(at), Format.person_name(person)}

  defp card(%Person{} = person, rows, now, grades) do
    sorted = Enum.sort_by(rows, & &1.activity.acted_at, {:desc, DateTime})
    %Card{person: person, acts: acts(sorted, person, grades, now)}
  end

  # One row per title in the order the titles first appear — newest
  # first, since the rows are sorted — with every act on it behind it.
  defp acts(sorted, person, grades, now) do
    by_ref = Enum.group_by(sorted, &ref/1)

    sorted
    |> Enum.map(&ref/1)
    |> Enum.uniq()
    |> Enum.map(&act(&1, Map.fetch!(by_ref, &1), person, grades, now))
  end

  defp act(ref, [%{activity: %Activity{} = newest} = first | _rest] = rows, person, grades, now) do
    flags = rows |> Enum.map(&Flag.flag(&1.activity)) |> Flag.sort()

    %FeedEntry{
      id: "person-row-" <> newest.id,
      activity_id: newest.id,
      ref: ref,
      title: newest.title,
      poster_url: first.poster_url,
      author: nil,
      subject: ActivityWords.subject(person),
      kind: newest.kind,
      episode: newest.episode,
      glyphs: Enum.map(flags, &{&1, Map.fetch!(grades, {ref, &1})}),
      text: review_text(rows),
      acted_at: newest.acted_at,
      ago: Format.relative_ago(newest.acted_at, now: now, sub_minute: :just_now),
      slots: ToolbarSlots.resolve(first)
    }
  end

  # The review's words on the title, whichever act is newest.
  defp review_text(rows) do
    Enum.find_value(rows, fn
      %{activity: %Activity{kind: :review, text: text}} -> text
      _other -> nil
    end)
  end

  defp ref(%{activity: %Activity{tmdb_id: tmdb_id, media_type: media_type}}), do: {tmdb_id, media_type}

  @doc """
  Why the Friends tab has no friends (UIDR-034): no relay first — Social is
  on for everyone, and a friend is a key on a relay you share — then no
  friends; nil once one exists. The reader's own card does not count.
  """
  @spec empty_reason(boolean(), non_neg_integer()) :: :no_relay | :no_friends | nil
  def empty_reason(false, _friend_count), do: :no_relay
  def empty_reason(true, 0), do: :no_friends
  def empty_reason(true, _friend_count), do: nil
end
