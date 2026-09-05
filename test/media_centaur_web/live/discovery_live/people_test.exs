defmodule MediaCentaurWeb.DiscoveryLive.PeopleTest do
  use ExUnit.Case, async: true

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

  test "You first, then friends by latest activity, the quiet ones last by name" do
    people =
      People.build(
        [
          activity("Alice", @alice, %{tmdb_id: 1, acted_at: ~U[2026-09-01 12:00:00Z]}),
          activity("Bob", @bob, %{tmdb_id: 2, kind: :watched, acted_at: ~U[2026-09-03 10:00:00Z]}),
          activity_row(%{own?: true, nickname: nil, activity: %{tmdb_id: 3, author_pubkey: "me"}})
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

  test "a person's shelves are their activities by kind, newest first, with the presence line" do
    episode = %Episode{season_number: 2, episode_number: 5}

    [bob | _rest] =
      People.build(
        [
          activity("Bob", @bob, %{
            tmdb_id: 1399,
            media_type: :tv_series,
            name: "Sample Show",
            kind: :watched,
            episode: episode,
            acted_at: ~U[2026-09-03 10:00:00Z]
          }),
          activity("Bob", @bob, %{tmdb_id: 7, kind: :watched, acted_at: ~U[2026-09-01 10:00:00Z]}),
          activity("Bob", @bob, %{tmdb_id: 8, kind: :tracking, acted_at: ~U[2026-09-02 10:00:00Z]}),
          activity("Bob", @bob, %{
            tmdb_id: 9,
            sentiment: :love,
            note: "Yes.",
            acted_at: ~U[2026-08-20 10:00:00Z]
          })
        ],
        [friend(@bob, "Bob", ~U[2026-08-30 10:00:00Z])],
        me: false,
        now: @now
      )

    assert bob.presence == %{
             text: "watched S02E05 of Sample Show",
             ago: "2h ago",
             at: ~U[2026-09-03 10:00:00Z]
           }

    assert Enum.map(bob.watched, & &1.ref) == [{1399, :tv_series}, {7, :movie}]
    assert [%Person.Entry{episode: ^episode, activity_id: "activity-1399-watched"} | _] = bob.watched
    assert Enum.map(bob.tracking, & &1.ref) == [{8, :movie}]
    assert [%Person.Entry{sentiment: :love, ref: {9, :movie}}] = bob.recommended
    assert bob.short_npub =~ "npub1"
    assert bob.added_on == ~D[2026-08-30]
  end

  test "a former friend's activity has no card, and a quiet friend has no presence" do
    people =
      People.build(
        [activity_row(%{nickname: nil, own?: false, activity: %{tmdb_id: 1, author_pubkey: "gone"}})],
        [friend(@cleo, "Cleo", ~U[2026-09-02 10:00:00Z])],
        me: false,
        now: @now
      )

    assert [%Person{name: "Cleo", presence: nil, watched: [], tracking: [], recommended: []}] = people
  end
end
