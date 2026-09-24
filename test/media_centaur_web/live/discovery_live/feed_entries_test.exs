defmodule MediaCentaurWeb.DiscoveryLive.FeedEntriesTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows, only: [activity_row: 1]

  alias MediaCentaurWeb.Components.Discovery.FeedEntry
  alias MediaCentaurWeb.DiscoveryLive.FeedEntries

  @now ~U[2026-09-01 14:00:00Z]

  defp row(nickname, attrs, overrides \\ %{}) do
    activity_row(Map.merge(%{nickname: nickname, activity: attrs}, overrides))
  end

  defp build(rows, opts \\ []) do
    FeedEntries.build(
      rows,
      Keyword.merge([now: @now, window: FeedEntries.page_size(), scope: :everyone], opts)
    )
  end

  describe "build/2" do
    test "keeps every author's reviews and listings; drops watched, former-friend, ignored" do
      %{entries: entries, has_older?: false} =
        build([
          row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo-lists-1"}),
          row("Nick", %{tmdb_id: 2, kind: :review, id: "nick-recs-2"}),
          row("Nick", %{tmdb_id: 3, kind: :watched, id: "nick-watched-3"}),
          row(nil, %{tmdb_id: 4, kind: :review, id: "mine"}, %{own?: true}),
          row(nil, %{tmdb_id: 41, kind: :watched, id: "mine-watched"}, %{own?: true}),
          row(nil, %{tmdb_id: 5, kind: :listing, id: "gone"}, %{own?: false}),
          row("Sam", %{tmdb_id: 6, kind: :review, id: "ignored"}, %{rung: :ignored}),
          row(nil, %{tmdb_id: 7, kind: :review, id: "mine-ignored"}, %{own?: true, rung: :ignored})
        ])

      assert Enum.map(entries, & &1.activity_id) == ["cleo-lists-1", "nick-recs-2", "mine"]
    end

    test "the entry rule holds under every scope; the scope drops the other authors" do
      rows = [
        row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo", acted_at: ~U[2026-09-01 13:00:00Z]}),
        row(nil, %{tmdb_id: 2, kind: :review, id: "mine", acted_at: ~U[2026-09-01 12:00:00Z]}, %{
          own?: true
        }),
        row("Nick", %{tmdb_id: 3, kind: :watched, id: "nick-watched"}),
        row(
          nil,
          %{tmdb_id: 4, kind: :listing, id: "mine-listing", acted_at: ~U[2026-09-01 11:00:00Z]},
          %{own?: true}
        )
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
        row(nil, %{tmdb_id: 4, kind: :review, id: "mine", acted_at: ~U[2026-09-01 10:00:00Z]}, %{
          own?: true
        })
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

    test "the window bounds the entries and says whether older ones exist" do
      rows = for id <- 1..3, do: row("Nick", %{tmdb_id: id, kind: :listing, id: "act-#{id}"})

      assert %{entries: [_, _], has_older?: true} = build(rows, window: 2)
      assert %{entries: [_, _, _], has_older?: false} = build(rows, window: 3)
      assert %{entries: [_, _, _], has_older?: false} = build(rows, window: 50)
      assert FeedEntries.page_size() == 50
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
          row(
            nil,
            %{tmdb_id: 11, kind: :listing, id: "mine-11", acted_at: ~U[2026-09-01 11:00:00Z]},
            %{own?: true, rung: :list}
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
               author: "Nick",
               own?: false,
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

      assert %FeedEntry{author: "You", own?: true, kind: :listing, list_slot: :listed} = own

      assert %FeedEntry{
               author: "Cleo",
               own?: false,
               kind: :listing,
               sentiment: nil,
               text: nil,
               ago: "1d ago",
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
