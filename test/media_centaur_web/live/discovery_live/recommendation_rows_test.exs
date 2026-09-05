defmodule MediaCentaurWeb.DiscoveryLive.RecommendationRowsTest do
  use ExUnit.Case, async: true

  import MediaCentaur.DiscoveryRows

  alias MediaCentaurWeb.DiscoveryLive.RecommendationRows

  @now ~U[2026-09-03 12:00:00Z]

  defp friend(name, tmdb_id, opts \\ []) do
    activity_row(%{
      nickname: name,
      own?: false,
      activity: %{
        tmdb_id: tmdb_id,
        id: "#{name}-#{tmdb_id}",
        note: opts[:note],
        sentiment: opts[:sentiment] || :like,
        acted_at: opts[:at] || ~U[2026-09-01 12:00:00Z]
      }
    })
  end

  test "one row per title, placed by its newest recommendation, friends only" do
    rows =
      RecommendationRows.build(
        [
          friend("Bob", 1, at: ~U[2026-09-01 12:00:00Z]),
          friend("Alice", 2, at: ~U[2026-09-02 12:00:00Z]),
          friend("Cleo", 1, at: ~U[2026-09-03 11:00:00Z]),
          activity_row(%{own?: true, nickname: nil, activity: %{tmdb_id: 3}}),
          activity_row(%{nickname: "Bob", activity: %{tmdb_id: 4, kind: :watched}}),
          activity_row(%{nickname: nil, own?: false, activity: %{tmdb_id: 5}})
        ],
        now: @now
      )

    assert Enum.map(rows, & &1.ref) == [{1, :movie}, {2, :movie}]

    [movie_one, _movie_two] = rows
    assert Enum.map(movie_one.activities, & &1.nickname) == ["Cleo", "Bob"]
    assert movie_one.lead == "Cleo, Bob · 1h ago"
    assert movie_one.title.name == "Sample Movie 1"
  end

  test "a lone recommender's note is plain; several recommenders attribute theirs" do
    [alone] = RecommendationRows.build([friend("Bob", 1, note: "Watch it.")], now: @now)
    assert alone.notes == [%{name: nil, text: "Watch it."}]

    [shared] =
      RecommendationRows.build(
        [
          friend("Bob", 1, note: "Watch it.", at: ~U[2026-09-01 12:00:00Z]),
          friend("Alice", 1, at: ~U[2026-09-02 12:00:00Z]),
          friend("Cleo", 1, note: "Bob's right.", at: ~U[2026-09-03 11:00:00Z])
        ],
        now: @now
      )

    assert shared.notes == [%{name: "Cleo", text: "Bob's right."}, %{name: "Bob", text: "Watch it."}]

    [silent] = RecommendationRows.build([friend("Bob", 1)], now: @now)
    assert silent.notes == []
  end

  test "the row carries the page's joins from the rows that fed it" do
    [row] =
      RecommendationRows.build(
        [
          activity_row(%{
            nickname: "Bob",
            activity: %{tmdb_id: 1},
            poster_url: "/p.jpg",
            library_owner_id: 9,
            on_watchlist?: true,
            acquisition_state: :downloading
          })
        ],
        now: @now
      )

    assert %{
             poster_url: "/p.jpg",
             library_owner_id: 9,
             on_watchlist?: true,
             acquisition_state: :downloading
           } =
             row
  end
end
