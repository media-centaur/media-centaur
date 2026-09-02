defmodule MediaCentaur.Repo.DataMigrations.BackfillWatchlistTitleEmbedTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Discovery
  alias MediaCentaur.Discovery.WatchlistItem
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.BackfillWatchlistTitleEmbed
  alias MediaCentaur.TMDB.Title

  setup do
    MediaCentaur.TmdbStubs.setup_tmdb_client()
  end

  # A pre-embed row: the flat snapshot columns filled, `title` NULL.
  # New rows only write `name`, so the other flat columns are set by hand.
  defp insert_legacy_row do
    {:ok, item} =
      Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))

    Repo.query!(
      "UPDATE watchlist_items SET title = NULL, year = '2010', release_date = '2010-03-05', " <>
        "poster_path = '/p.jpg', overview = 'A sample overview.' WHERE tmdb_id = 777"
    )

    await_supervised_tasks()
    item.id
  end

  describe "backfill/1" do
    test "rebuilds the embedded title from the flat columns" do
      id = insert_legacy_row()

      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)

      assert %WatchlistItem{
               title: %Title{
                 tmdb_id: 777,
                 media_type: :movie,
                 name: "Sample Movie",
                 year: "2010",
                 release_date: ~D[2010-03-05],
                 poster_path: "/p.jpg",
                 backdrop_path: nil,
                 overview: "A sample overview."
               }
             } = Repo.get!(WatchlistItem, id)
    end

    test "is idempotent — a filled row is left alone" do
      id = insert_legacy_row()
      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)

      Repo.query!("UPDATE watchlist_items SET name = 'Renamed' WHERE tmdb_id = 777")
      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)

      assert %WatchlistItem{title: %Title{name: "Sample Movie"}} = Repo.get!(WatchlistItem, id)
    end

    test "no-op on an empty table" do
      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)
    end
  end
end
