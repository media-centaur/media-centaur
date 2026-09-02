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

  # The flat snapshot columns were dropped by `DropWatchlistFlatColumns`;
  # this migration still has to work on an install that skipped straight
  # past that release. Re-create them for the test (SQLite DDL is
  # transactional, so the sandbox rolls them back).
  defp restore_flat_columns do
    for {column, type} <- [
          name: "TEXT",
          year: "TEXT",
          release_date: "DATE",
          poster_path: "TEXT",
          overview: "TEXT"
        ] do
      Repo.query!("ALTER TABLE watchlist_items ADD COLUMN #{column} #{type}")
    end

    :ok
  end

  # A pre-embed row: the flat snapshot columns filled, `title` NULL.
  defp insert_legacy_row do
    restore_flat_columns()

    {:ok, item} =
      Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"}))

    Repo.query!(
      "UPDATE watchlist_items SET title = NULL, name = 'Sample Movie', year = '2010', " <>
        "release_date = '2010-03-05', poster_path = '/p.jpg', overview = 'A sample overview.' " <>
        "WHERE tmdb_id = 777"
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

  describe "flat_columns_present?/1" do
    test "is false on the current schema and true while the flat snapshot columns exist" do
      refute BackfillWatchlistTitleEmbed.flat_columns_present?(Repo)
      restore_flat_columns()
      assert BackfillWatchlistTitleEmbed.flat_columns_present?(Repo)
    end

    test "backfill is a no-op once the flat columns are gone" do
      {:ok, item} =
        Discovery.add_to_watchlist(Title.new!(%{tmdb_id: 778, media_type: :movie, name: "Sample Movie"}))

      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)
      assert %WatchlistItem{title: %Title{name: "Sample Movie"}} = Repo.get!(WatchlistItem, item.id)
      await_supervised_tasks()
    end
  end

  describe "column_present?/3" do
    test "reads the table's columns from PRAGMA table_info" do
      assert BackfillWatchlistTitleEmbed.column_present?(Repo, "watchlist_items", "tmdb_id")
      refute BackfillWatchlistTitleEmbed.column_present?(Repo, "watchlist_items", "year")
    end
  end
end
