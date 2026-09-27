defmodule MediaCentaurWeb.DiscoveryLive.PeopleTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Discovery.Act.Entry
  alias MediaCentaurWeb.DiscoveryLive.People
  alias MediaCentaurWeb.DiscoveryLive.People.Card

  @now ~U[2026-09-03 12:00:00Z]
  @me "0101010101010101010101010101010101010101010101010101010101010101"
  @bob "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @alice "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
  @cleo "e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd13"

  defp friend(pubkey, name, added),
    do: %Person{pubkey: pubkey, name_override: name, own?: false, short_npub: "npub1…", added_on: added}

  # The known people, with or without the reader.
  defp people(me?) do
    friends = [
      friend(@alice, "Alice", ~D[2026-08-30]),
      friend(@bob, "Bob", ~D[2026-08-30]),
      friend(@cleo, "Cleo", ~D[2026-09-02])
    ]

    base = Map.new(friends, &{&1.pubkey, &1})
    if me?, do: Map.put(base, @me, own_person(@me)), else: base
  end

  defp activity(name, pubkey, attrs) do
    activity_row(%{
      author: person(name, pubkey: pubkey),
      activity: Map.put(attrs, :author_pubkey, pubkey)
    })
  end

  defp own(attrs) do
    activity_row(%{author: own_person(@me), activity: Map.put(attrs, :author_pubkey, @me)})
  end

  defp names(cards), do: Enum.map(cards, &Format.person_name(&1.person))

  test "You first, then friends by latest act, the quiet ones last by name" do
    people =
      People.build(
        [
          activity("Alice", @alice, %{tmdb_id: 1, acted_at: ~U[2026-09-01 12:00:00Z]}),
          activity("Bob", @bob, %{tmdb_id: 2, kind: :watched, acted_at: ~U[2026-09-03 10:00:00Z]}),
          own(%{tmdb_id: 3})
        ],
        people(true),
        now: @now
      )

    assert names(people) == ["You", "Bob", "Alice", "Cleo"]
    assert [%Card{person: %Person{own?: true, pubkey: @me}} | _friends] = people
  end

  test "without an identity there is no You card" do
    assert ["Alice" | _rest] = names(People.build([], people(false), now: @now))
    assert length(People.build([], people(false), now: @now)) == 3
  end

  test "a person's acts are one per title, newest first, flying every act on it in mast order" do
    episode = %Episode{season_number: 1, episode_number: 3}

    [bob | _rest] =
      People.build(
        [
          activity("Bob", @bob, %{
            tmdb_id: 7,
            kind: :watched,
            id: "w7",
            acted_at: ~U[2026-09-03 10:00:00Z]
          }),
          activity("Bob", @bob, %{
            tmdb_id: 7,
            kind: :review,
            sentiment: :love,
            id: "r7",
            acted_at: ~U[2026-09-03 09:00:00Z]
          }),
          activity("Bob", @bob, %{
            tmdb_id: 9,
            kind: :watched,
            episode: episode,
            id: "w9a",
            acted_at: ~U[2026-09-02 10:00:00Z],
            media_type: :tv_series
          }),
          activity("Bob", @bob, %{
            tmdb_id: 9,
            kind: :watched,
            episode: %Episode{season_number: 1, episode_number: 2},
            id: "w9b",
            acted_at: ~U[2026-09-02 09:00:00Z],
            media_type: :tv_series
          }),
          activity("Bob", @bob, %{
            tmdb_id: 11,
            kind: :listing,
            id: "l11",
            acted_at: ~U[2026-09-01 10:00:00Z]
          })
        ],
        %{@bob => friend(@bob, "Bob", ~D[2026-08-30])},
        now: @now
      )

    assert Enum.map(bob.acts, &{&1.ref, &1.flags, &1.activity_id}) == [
             {{7, :movie}, [:love, :watched], "w7"},
             {{9, :tv_series}, [:watched], "w9a"},
             {{11, :movie}, [:listing], "l11"}
           ]

    # A binge is one poster with one eye; the episodes are the opened card's rows.
    assert Enum.map(Enum.at(bob.acts, 1).entries, & &1.activity_id) == ["w9a", "w9b"]
    assert Enum.at(bob.acts, 1).episode == episode

    assert [%Entry{kind: :watched, flag: :watched}, %Entry{kind: :review, flag: :love}] =
             hd(bob.acts).entries

    assert hd(bob.acts).acted_at == ~U[2026-09-03 10:00:00Z]
    assert Enum.map(bob.acts, & &1.ago) == ["2h ago", "1d ago", "2d ago"]

    # The card carries the person as the people map gave them.
    assert bob.person == friend(@bob, "Bob", ~D[2026-08-30])
  end

  test "a flag is gold when two or more friends did that act on that title; own acts count the roster, not the reader" do
    people =
      People.build(
        [
          activity("Alice", @alice, %{
            tmdb_id: 7,
            kind: :review,
            sentiment: :love,
            id: "a7",
            acted_at: ~U[2026-09-03 10:00:00Z]
          }),
          activity("Bob", @bob, %{
            tmdb_id: 7,
            kind: :review,
            sentiment: :love,
            id: "b7",
            acted_at: ~U[2026-09-03 09:00:00Z]
          }),
          activity("Cleo", @cleo, %{
            tmdb_id: 7,
            kind: :watched,
            id: "c7a",
            acted_at: ~U[2026-09-03 08:00:00Z]
          }),
          activity("Cleo", @cleo, %{
            tmdb_id: 7,
            kind: :watched,
            id: "c7b",
            acted_at: ~U[2026-09-03 07:00:00Z]
          }),
          activity("Bob", @bob, %{
            tmdb_id: 11,
            kind: :listing,
            id: "b11",
            acted_at: ~U[2026-09-02 10:00:00Z]
          }),
          own(%{
            tmdb_id: 7,
            kind: :review,
            sentiment: :love,
            id: "me7",
            acted_at: ~U[2026-09-03 11:00:00Z]
          }),
          own(%{tmdb_id: 11, kind: :listing, id: "me11", acted_at: ~U[2026-09-02 11:00:00Z]})
        ],
        people(true),
        now: @now
      )

    by_name = Map.new(people, &{Format.person_name(&1.person), &1})
    acts = fn card -> Map.new(card.acts, &{&1.ref, {&1.flags, &1.gold}}) end

    # Two friends loved 7: gold on every card that flies love there — the reader's included.
    assert acts.(by_name["You"]) == %{
             {7, :movie} => {[:love], [:love]},
             {11, :movie} => {[:listing], []}
           }

    assert acts.(by_name["Alice"]) == %{{7, :movie} => {[:love], [:love]}}

    assert acts.(by_name["Bob"]) == %{
             {7, :movie} => {[:love], [:love]},
             {11, :movie} => {[:listing], []}
           }

    # One friend watched 7, twice: a friend counts once per act on a title.
    assert acts.(by_name["Cleo"]) == %{{7, :movie} => {[:watched], []}}
  end

  test "a quiet friend is a card with no acts" do
    people = People.build([], %{@cleo => friend(@cleo, "Cleo", ~D[2026-09-02])}, now: @now)

    assert [%Card{person: %Person{name_override: "Cleo"}, acts: []}] = people
  end

  test "rail/1 takes You and the seven most recent, and counts who the cap hid" do
    people =
      for index <- 1..12,
          do: %Card{
            person: %Person{
              pubkey: String.pad_leading("#{index}", 64, "0"),
              name_override: "Friend #{index}"
            }
          }

    you = %Card{person: own_person(@me)}

    assert %{cards: shown, hidden: 5} = People.rail([you | people])
    assert length(shown) == 8
    assert hd(shown).person.own?

    assert %{cards: [^you], hidden: 0} = People.rail([you])
  end
end
