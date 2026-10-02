defmodule MediaCentaurWeb.SocialLive.FeedEntriesTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [activity_row: 1, person: 1, own_person: 0]

  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.FeedEntry
  alias MediaCentaurWeb.SocialLive.FeedEntries

  @now ~U[2026-09-01 14:00:00Z]

  defp row(name, attrs, overrides \\ %{}) do
    activity_row(Map.merge(%{author: person(name), activity: attrs}, overrides))
  end

  defp own(attrs, overrides \\ %{}) do
    activity_row(Map.merge(%{author: own_person(), activity: attrs}, overrides))
  end

  defp build(rows, opts \\ []) do
    FeedEntries.build(
      rows,
      Keyword.merge([now: @now, window: FeedEntries.page_size(), scope: :everyone, head: nil], opts)
    )
  end

  describe "build/2" do
    test "keeps every author's reviews and listings; drops watched and ignored" do
      %{entries: entries, has_older?: false} =
        build([
          row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo-lists-1"}),
          row("Nick", %{tmdb_id: 2, kind: :review, id: "nick-recs-2"}),
          row("Nick", %{tmdb_id: 3, kind: :watched, id: "nick-watched-3"}),
          own(%{tmdb_id: 4, kind: :review, id: "mine"}),
          own(%{tmdb_id: 41, kind: :watched, id: "mine-watched"}),
          row("Sam", %{tmdb_id: 6, kind: :review, id: "ignored"}, %{rung: :ignored}),
          own(%{tmdb_id: 7, kind: :review, id: "mine-ignored"}, %{rung: :ignored})
        ])

      assert Enum.map(entries, & &1.activity_id) == ["cleo-lists-1", "nick-recs-2", "mine"]
    end

    test "the entry rule holds under every scope; the scope drops the other authors" do
      rows = [
        row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo", acted_at: ~U[2026-09-01 13:00:00Z]}),
        own(%{tmdb_id: 2, kind: :review, id: "mine", acted_at: ~U[2026-09-01 12:00:00Z]}),
        row("Nick", %{tmdb_id: 3, kind: :watched, id: "nick-watched"}),
        own(%{tmdb_id: 4, kind: :listing, id: "mine-listing", acted_at: ~U[2026-09-01 11:00:00Z]})
      ]

      ids = fn scope -> Enum.map(build(rows, scope: scope).entries, & &1.activity_id) end

      assert ids.(:everyone) == ["cleo", "mine", "mine-listing"]
      assert ids.(:friends) == ["cleo"]
      assert ids.(:you) == ["mine", "mine-listing"]
    end

    test "the scope is applied before the window, so has_older? and the count are the scope's" do
      rows = [
        row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo-1", acted_at: ~U[2026-09-01 13:00:00Z]}),
        row("Nick", %{tmdb_id: 2, kind: :listing, id: "nick-2", acted_at: ~U[2026-09-01 12:00:00Z]}),
        row("Sam", %{tmdb_id: 3, kind: :listing, id: "sam-3", acted_at: ~U[2026-09-01 11:00:00Z]}),
        own(%{tmdb_id: 4, kind: :review, id: "mine", acted_at: ~U[2026-09-01 10:00:00Z]})
      ]

      assert build(rows, scope: :everyone, window: 3).has_older?
      refute build(rows, scope: :friends, window: 3).has_older?
      assert [%FeedEntry{activity_id: "mine"}] = build(rows, scope: :you, window: 3).entries
    end

    test "one entry per action, newest first, never grouped" do
      %{entries: entries} =
        build([
          row("Nick", %{tmdb_id: 7, kind: :listing, id: "nick-lists", acted_at: ~U[2026-09-01 12:05:00Z]}),
          row("Nick", %{
            tmdb_id: 7,
            kind: :review,
            id: "nick-recs",
            acted_at: ~U[2026-09-01 12:00:00Z]
          }),
          row("Cleo", %{
            tmdb_id: 7,
            kind: :review,
            id: "cleo-recs",
            acted_at: ~U[2026-09-01 11:00:00Z]
          }),
          row("Sam", %{tmdb_id: 8, kind: :listing, id: "sam-lists", acted_at: ~U[2026-09-01 13:00:00Z]})
        ])

      assert Enum.map(entries, & &1.activity_id) == ["sam-lists", "nick-lists", "nick-recs", "cleo-recs"]
      assert Enum.map(entries, & &1.ref) == [{8, :movie}, {7, :movie}, {7, :movie}, {7, :movie}]
    end

    test "the window is twenty, Show older adds twenty, sixty is the cap" do
      rows =
        for id <- 1..70,
            do:
              row("Nick", %{
                tmdb_id: id,
                kind: :listing,
                id: "act-#{id}",
                acted_at: DateTime.add(@now, -id, :minute)
              })

      assert FeedEntries.page_size() == 20
      assert FeedEntries.cap() == 60
      assert %{entries: entries, has_older?: true, at_cap?: false} = build(rows, window: 20)
      assert length(entries) == 20
      assert %{has_older?: true, at_cap?: false} = build(rows, window: 40)
      assert %{entries: entries, has_older?: false, at_cap?: true} = build(rows, window: 60)
      assert length(entries) == 60
      assert %{has_older?: false, at_cap?: false} = build(Enum.take(rows, 45), window: 60)
      # A window past the cap is the cap.
      assert %{entries: entries} = build(rows, window: 80)
      assert length(entries) == 60
    end

    test "a head freezes the window at the newest band shown and counts what arrived above it as queued" do
      rows =
        for id <- 1..5,
            do:
              row("Nick", %{
                tmdb_id: id,
                kind: :listing,
                id: "act-#{id}",
                acted_at: DateTime.add(@now, -id, :minute)
              })

      assert %{entries: entries, queued: 0} = build(rows, head: nil)
      assert Enum.map(entries, & &1.activity_id) == ~w(act-1 act-2 act-3 act-4 act-5)

      assert %{entries: entries, queued: 2} = build(rows, head: "act-3")
      assert Enum.map(entries, & &1.activity_id) == ~w(act-3 act-4 act-5)

      # A head the list no longer holds (withdrawn) is live again.
      assert %{queued: 0, entries: [_, _, _, _, _]} = build(rows, head: "gone")
    end

    test "the queue is counted in the scope" do
      rows = [
        row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo", acted_at: ~U[2026-09-01 13:00:00Z]}),
        own(%{tmdb_id: 2, kind: :review, id: "mine", acted_at: ~U[2026-09-01 12:30:00Z]}),
        row("Nick", %{tmdb_id: 3, kind: :listing, id: "nick", acted_at: ~U[2026-09-01 12:00:00Z]})
      ]

      assert build(rows, scope: :everyone, head: "nick").queued == 2
      assert build(rows, scope: :friends, head: "nick").queued == 1
    end

    test "an entry carries what the row shows and the facts the toolbar resolves from" do
      %{entries: [review, own, listing]} =
        build([
          row(
            "Nick",
            %{
              tmdb_id: 9,
              kind: :review,
              id: "nick-recs-9",
              sentiment: :love,
              text: "Saw it twice.",
              acted_at: ~U[2026-09-01 12:00:00Z]
            },
            %{
              poster_url: "/p.jpg",
              rung: :list,
              library_owner_id: "owner",
              acquisition_state: :downloading
            }
          ),
          own(
            %{tmdb_id: 11, kind: :listing, id: "mine-11", acted_at: ~U[2026-09-01 11:00:00Z]},
            %{rung: :list}
          ),
          row("Cleo", %{
            tmdb_id: 10,
            kind: :listing,
            id: "cleo-lists-10",
            acted_at: ~U[2026-08-31 14:00:00Z]
          })
        ])

      assert %FeedEntry{
               id: "feed-row-nick-recs-9",
               activity_id: "nick-recs-9",
               ref: {9, :movie},
               author: %Person{name_override: "Nick", own?: false},
               kind: :review,
               sentiment: :love,
               text: "Saw it twice.",
               ago: "2h ago",
               poster_url: "/p.jpg",
               rung: :list,
               library_owner_id: "owner",
               acquisition_state: :downloading,
               list_slot: :listed,
               download_slot: {:state, "In library"}
             } = review

      assert review.title.name == "Sample Movie 9"

      assert %FeedEntry{author: %Person{own?: true}, kind: :listing, list_slot: :listed} = own

      assert %FeedEntry{
               author: %Person{name_override: "Cleo", own?: false},
               kind: :listing,
               sentiment: nil,
               text: nil,
               ago: "1d ago",
               poster_url: nil,
               rung: nil,
               list_slot: :list,
               download_slot: :download
             } = listing
    end
  end

  describe "parse_scope/1" do
    test "the URL's word, Everyone for anything else" do
      assert FeedEntries.parse_scope("friends") == :friends
      assert FeedEntries.parse_scope("you") == :you
      assert FeedEntries.parse_scope("everyone") == :everyone
      assert FeedEntries.parse_scope(nil) == :everyone
      assert FeedEntries.parse_scope("nonsense") == :everyone
    end

    test "scope_query/1 is its inverse: Everyone is the bare address" do
      assert FeedEntries.scope_query(:everyone) == []
      assert FeedEntries.scope_query(:friends) == [scope: "friends"]
      assert FeedEntries.scope_query(:you) == [scope: "you"]

      for scope <- [:everyone, :friends, :you] do
        assert scope |> FeedEntries.scope_query() |> Keyword.get(:scope) |> FeedEntries.parse_scope() ==
                 scope
      end
    end
  end

  describe "empty_reason/2" do
    test "You never needs a relay or a friend; the other scopes diagnose readiness first" do
      assert FeedEntries.empty_reason(:you, false) == :nothing_shared
      assert FeedEntries.empty_reason(:you, true) == :nothing_shared
      assert FeedEntries.empty_reason(:everyone, false) == :not_ready
      assert FeedEntries.empty_reason(:friends, false) == :not_ready
      assert FeedEntries.empty_reason(:everyone, true) == :quiet
      assert FeedEntries.empty_reason(:friends, true) == :quiet
    end
  end

  describe "list_slot/1" do
    test "List below the list, Listed on it, Following above it" do
      assert FeedEntries.list_slot(%{rung: nil}) == :list
      assert FeedEntries.list_slot(%{rung: :ignored}) == :list
      assert FeedEntries.list_slot(%{rung: :list}) == :listed

      for rung <- [:follow, :grab],
          do: assert(FeedEntries.list_slot(%{rung: rung}) == :following)
    end
  end

  describe "download_slot/1" do
    test "the library wins, then the acquisition state, else the verb" do
      assert FeedEntries.download_slot(%{library_owner_id: "x", acquisition_state: :downloading}) ==
               {:state, "In library"}

      assert FeedEntries.download_slot(%{library_owner_id: nil, acquisition_state: :downloading}) ==
               {:state, "Downloading"}

      assert FeedEntries.download_slot(%{library_owner_id: nil, acquisition_state: :planning}) ==
               {:state, "Planning"}

      assert FeedEntries.download_slot(%{library_owner_id: nil, acquisition_state: :needs_review}) ==
               {:state, "Needs review"}

      assert FeedEntries.download_slot(%{library_owner_id: nil, acquisition_state: nil}) == :download
    end
  end
end
