defmodule MediaCentaurWeb.DiscoveryLive.PeopleTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Social.Friend
  alias MediaCentaurWeb.Components.Discovery.Person
  alias MediaCentaurWeb.DiscoveryLive.People

  @now ~U[2026-09-03 12:00:00Z]
  @bob "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @alice "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
  @cleo "e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd13"

  defp friend(pubkey, name, added) do
    %Friend{pubkey: pubkey, nickname: name, inserted_at: added}
  end

  defp friends do
    [
      friend(@alice, "Alice", ~U[2026-08-30 10:00:00Z]),
      friend(@bob, "Bob", ~U[2026-08-30 10:00:00Z]),
      friend(@cleo, "Cleo", ~U[2026-09-02 10:00:00Z])
    ]
  end

  defp activity(name, pubkey, attrs) do
    activity_row(%{nickname: name, activity: Map.put(attrs, :author_pubkey, pubkey)})
  end

  defp own(attrs) do
    activity_row(%{own?: true, nickname: nil, activity: Map.put(attrs, :author_pubkey, "me")})
  end

  test "You first, then friends by latest act, the quiet ones last by name" do
    people =
      People.build(
        [
          activity("Alice", @alice, %{tmdb_id: 1, acted_at: ~U[2026-09-01 12:00:00Z]}),
          activity("Bob", @bob, %{tmdb_id: 2, kind: :watched, acted_at: ~U[2026-09-03 10:00:00Z]}),
          own(%{tmdb_id: 3})
        ],
        friends(),
        me: true,
        now: @now
      )

    assert Enum.map(people, & &1.name) == ["You", "Bob", "Alice", "Cleo"]
    assert [%Person{own?: true, id: "person-you", pubkey: nil} | _friends] = people
  end

  test "without an identity there is no You card" do
    assert [%Person{name: "Alice"} | _rest] = People.build([], friends(), me: false, now: @now)
    assert length(People.build([], friends(), me: false, now: @now)) == 3
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
        [friend(@bob, "Bob", ~U[2026-08-30 10:00:00Z])],
        me: false,
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

    assert [%Person.Entry{kind: :watched, flag: :watched}, %Person.Entry{kind: :review, flag: :love}] =
             hd(bob.acts).entries

    assert hd(bob.acts).acted_at == ~U[2026-09-03 10:00:00Z]
    assert Enum.map(bob.acts, & &1.ago) == ["2h ago", "1d ago", "2d ago"]
    assert bob.short_npub =~ "npub1"
    assert bob.added_on == ~D[2026-08-30]
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
        friends(),
        me: true,
        now: @now
      )

    by_name = Map.new(people, &{&1.name, &1})
    acts = fn person -> Map.new(person.acts, &{&1.ref, {&1.flags, &1.gold}}) end

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

  test "a former friend's activity has no card, and a quiet friend has no acts" do
    people =
      People.build(
        [activity_row(%{nickname: nil, own?: false, activity: %{tmdb_id: 1, author_pubkey: "gone"}})],
        [friend(@cleo, "Cleo", ~U[2026-09-02 10:00:00Z])],
        me: false,
        now: @now
      )

    assert [%Person{name: "Cleo", acts: []}] = people
  end

  test "rail/1 takes You and the seven most recent, and counts who the cap hid" do
    people = for index <- 1..12, do: %Person{id: "p#{index}", name: "Friend #{index}", own?: false}
    you = %Person{id: "person-you", name: "You", own?: true}

    assert %{people: shown, hidden: 5} = People.rail([you | people])
    assert length(shown) == 8
    assert hd(shown).own?

    assert %{people: [^you], hidden: 0} = People.rail([you])
  end
end
