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
    FeedEntries.build(rows, Keyword.merge([now: @now, window: FeedEntries.page_size()], opts))
  end

  describe "build/2" do
    test "keeps friends' recommendations and listings; drops watched, own, former-friend, ignored" do
      %{entries: entries, has_older?: false} =
        build([
          row("Cleo", %{tmdb_id: 1, kind: :listing, id: "cleo-lists-1"}),
          row("Nick", %{tmdb_id: 2, kind: :recommendation, id: "nick-recs-2"}),
          row("Nick", %{tmdb_id: 3, kind: :watched, id: "nick-watched-3"}),
          row(nil, %{tmdb_id: 4, kind: :recommendation, id: "mine"}, %{own?: true}),
          row(nil, %{tmdb_id: 5, kind: :listing, id: "gone"}, %{own?: false}),
          row("Sam", %{tmdb_id: 6, kind: :recommendation, id: "ignored"}, %{rung: :ignored})
        ])

      assert Enum.map(entries, & &1.activity_id) == ["cleo-lists-1", "nick-recs-2"]
    end

    test "one entry per action, newest first, never grouped" do
      %{entries: entries} =
        build([
          row("Nick", %{tmdb_id: 7, kind: :listing, id: "nick-lists", acted_at: ~U[2026-09-01 12:05:00Z]}),
          row("Nick", %{
            tmdb_id: 7,
            kind: :recommendation,
            id: "nick-recs",
            acted_at: ~U[2026-09-01 12:00:00Z]
          }),
          row("Cleo", %{
            tmdb_id: 7,
            kind: :recommendation,
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

    test "an entry carries what the card shows and the facts the toolbar resolves from" do
      %{entries: [recommendation, listing]} =
        build([
          row(
            "Nick",
            %{
              tmdb_id: 9,
              kind: :recommendation,
              id: "nick-recs-9",
              sentiment: :love,
              note: "Saw it twice.",
              acted_at: ~U[2026-09-01 12:00:00Z]
            },
            %{
              poster_url: "/p.jpg",
              rung: :list,
              library_owner_id: "owner",
              acquisition_state: :downloading
            }
          ),
          row("Cleo", %{
            tmdb_id: 10,
            kind: :listing,
            id: "cleo-lists-10",
            acted_at: ~U[2026-08-31 14:00:00Z]
          })
        ])

      assert %FeedEntry{
               id: "feed-entry-nick-recs-9",
               activity_id: "nick-recs-9",
               ref: {9, :movie},
               nickname: "Nick",
               kind: :recommendation,
               sentiment: :love,
               note: "Saw it twice.",
               ago: "2h ago",
               poster_url: "/p.jpg",
               rung: :list,
               library_owner_id: "owner",
               acquisition_state: :downloading,
               list_slot: :listed,
               download_slot: {:state, "In library"}
             } = recommendation

      assert recommendation.title.name == "Sample Movie 9"

      assert %FeedEntry{
               kind: :listing,
               sentiment: nil,
               note: nil,
               ago: "1d ago",
               rung: nil,
               list_slot: :list,
               download_slot: :download
             } = listing
    end
  end

  describe "list_slot/1" do
    test "List below the list, Listed on it, Following above it" do
      assert FeedEntries.list_slot(%{rung: nil}) == :list
      assert FeedEntries.list_slot(%{rung: :ignored}) == :list
      assert FeedEntries.list_slot(%{rung: :list}) == :listed

      for rung <- [:follow, :ask, :grab, :default],
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
