defmodule MediaCentaurWeb.SocialLive.PeopleTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.Components.Social.ToolbarSlots
  alias MediaCentaurWeb.Components.Title.Grade
  alias MediaCentaurWeb.SocialLive.People
  alias MediaCentaurWeb.SocialLive.People.Card

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

  defp build(rows, people), do: People.build(rows, people, now: @now, grades: Grade.grades(rows))

  test "You first, then friends by latest act, the quiet ones last by name" do
    people =
      build(
        [
          activity("Alice", @alice, %{tmdb_id: 1, acted_at: ~U[2026-09-01 12:00:00Z]}),
          activity("Bob", @bob, %{tmdb_id: 2, kind: :watched, acted_at: ~U[2026-09-03 10:00:00Z]}),
          own(%{tmdb_id: 3})
        ],
        people(true)
      )

    assert names(people) == ["You", "Bob", "Alice", "Cleo"]
    assert [%Card{person: %Person{own?: true, pubkey: @me}} | _friends] = people
  end

  test "without an identity there is no You card" do
    assert ["Alice" | _rest] = names(build([], people(false)))
    assert length(build([], people(false))) == 3
  end

  test "a person's acts are one per title, newest first, showing every act on it in order" do
    episode = %Episode{season_number: 1, episode_number: 3}

    [bob | _rest] =
      build(
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
        %{@bob => friend(@bob, "Bob", ~D[2026-08-30])}
      )

    assert Enum.map(
             bob.acts,
             &{&1.ref, Enum.map(&1.glyphs, fn {flag, _grade} -> flag end), &1.activity_id}
           ) == [
             {{7, :movie}, [:love, :watched], "w7"},
             {{9, :tv_series}, [:watched], "w9a"},
             {{11, :movie}, [:listing], "l11"}
           ]

    # A binge is one poster with one eye, at the latest episode.
    assert %FeedEntry{id: "person-row-w9a", kind: :watched, episode: ^episode} = Enum.at(bob.acts, 1)
    assert %FeedEntry{kind: :watched, glyphs: [love: :plain, watched: :plain]} = hd(bob.acts)

    assert hd(bob.acts).acted_at == ~U[2026-09-03 10:00:00Z]
    assert Enum.map(bob.acts, & &1.ago) == ["2h ago", "1d ago", "2d ago"]

    # The card carries the person as the people map gave them.
    assert bob.person == friend(@bob, "Bob", ~D[2026-08-30])
  end

  test "each flag on an act carries its grade, counted over every person's acts on that title, the reader's included" do
    people =
      build(
        [
          activity("Alice", @alice, %{
            tmdb_id: 7,
            kind: :review,
            sentiment: :love,
            id: "a7",
            acted_at: ~U[2026-09-03 10:00:00Z]
          }),
          activity("Alice", @alice, %{
            tmdb_id: 7,
            kind: :watched,
            id: "a7w",
            acted_at: ~U[2026-09-03 09:30:00Z]
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
            sentiment: :like,
            id: "me7",
            acted_at: ~U[2026-09-03 11:00:00Z]
          }),
          own(%{tmdb_id: 11, kind: :listing, id: "me11", acted_at: ~U[2026-09-02 11:00:00Z]})
        ],
        people(true)
      )

    by_name = Map.new(people, &{Format.person_name(&1.person), &1})

    acts = fn card ->
      Map.new(
        card.acts,
        &{&1.ref, {Enum.map(&1.glyphs, fn {flag, _grade} -> flag end), Map.new(&1.glyphs)}}
      )
    end

    # On 7 Alice and Bob love it — two people, silver — and the reader's
    # like is one person, plain. Alice and Cleo watched it — Cleo once
    # however many rows — silver. On 11 Bob and the reader list it: silver.
    assert acts.(by_name["You"]) == %{
             {7, :movie} => {[:like], %{like: :plain}},
             {11, :movie} => {[:listing], %{listing: :silver}}
           }

    assert acts.(by_name["Alice"]) == %{
             {7, :movie} => {[:love, :watched], %{love: :silver, watched: :silver}}
           }

    assert acts.(by_name["Bob"]) == %{
             {7, :movie} => {[:love], %{love: :silver}},
             {11, :movie} => {[:listing], %{listing: :silver}}
           }

    assert acts.(by_name["Cleo"]) == %{{7, :movie} => {[:watched], %{watched: :silver}}}
  end

  test "a quiet friend is a card with no acts" do
    people = build([], %{@cleo => friend(@cleo, "Cleo", ~D[2026-09-02])})

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

  test "hidden/1 lists the hidden people by name" do
    shown = %Person{pubkey: String.duplicate("a", 64), name_override: "Shown"}
    hidden_a = %Person{pubkey: String.duplicate("b", 64), name_override: "Zed", hidden: true}
    hidden_b = %Person{pubkey: String.duplicate("c", 64), name_override: "Amy", hidden: true}
    people = Map.new([shown, hidden_a, hidden_b], &{&1.pubkey, &1})

    assert [^hidden_b, ^hidden_a] = People.hidden(people)
  end

  describe "empty_reason/2 — why the Friends tab has no friends" do
    test "no relay first, then no friends; nothing once a friend exists" do
      assert People.empty_reason(false, 0) == :no_relay
      assert People.empty_reason(false, 2) == :no_relay
      assert People.empty_reason(true, 0) == :no_friends
      assert People.empty_reason(true, 1) == nil
    end
  end

  test "an act is the page's row: one per title, the newest act's verb, every flag at its grade, the review's words, the title's slots" do
    rows = [
      activity("Bob", @bob, %{
        tmdb_id: 7,
        kind: :watched,
        id: "bob-watched-7",
        acted_at: ~U[2026-09-02 12:00:00Z]
      }),
      activity("Bob", @bob, %{
        tmdb_id: 7,
        kind: :review,
        sentiment: :love,
        text: "Yes.",
        id: "bob-loves-7",
        acted_at: ~U[2026-09-01 12:00:00Z]
      }),
      activity("Alice", @alice, %{tmdb_id: 7, kind: :review, sentiment: :love, id: "alice-loves-7"}),
      activity("Bob", @bob, %{
        tmdb_id: 1399,
        media_type: :tv_series,
        kind: :review,
        sentiment: nil,
        text: "Slow.",
        id: "bob-reviews-show",
        acted_at: ~U[2026-08-30 12:00:00Z]
      }),
      activity("Bob", @bob, %{
        tmdb_id: 1399,
        media_type: :tv_series,
        kind: :watched,
        episode: %Episode{season_number: 1, episode_number: 7, name: "Sample Episode"},
        id: "bob-watched-show",
        acted_at: ~U[2026-09-03 11:00:00Z]
      })
    ]

    [_you, %Card{person: %Person{pubkey: @bob}, acts: [show, movie]} | _rest] = build(rows, people(true))

    assert %FeedEntry{
             id: "person-row-bob-watched-show",
             activity_id: "bob-watched-show",
             author: nil,
             subject: :friend,
             kind: :watched
           } = show

    assert show.episode.name == "Sample Episode"
    assert show.glyphs == [{:review, :plain}, {:watched, :plain}]
    assert show.text == "Slow."

    assert %FeedEntry{id: "person-row-bob-watched-7", kind: :watched, episode: nil} = movie
    assert movie.glyphs == [{:love, :silver}, {:watched, :plain}]
    assert movie.text == "Yes."
    assert %ToolbarSlots{list: :list, download: :download} = movie.slots
  end

  test "the reader's own acts are rows in the second person" do
    [%Card{person: %Person{own?: true}, acts: [act]} | _friends] =
      build([own(%{tmdb_id: 3, kind: :listing})], people(true))

    assert act.subject == :you
    assert act.author == nil
  end
end
