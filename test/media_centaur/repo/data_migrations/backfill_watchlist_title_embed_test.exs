defmodule MediaCentaur.Repo.DataMigrations.BackfillWatchlistTitleEmbedTest do
  @moduledoc """
  `watchlist_items` is now `title_intents`, so this backfill can no
  longer find anything to fill — which is exactly the tolerance it was
  written with. What remains testable is that it recognises that and
  stops, rather than failing on a table it can no longer name.

  The rows it filled on the installs that ran it are unaffected: the
  table was renamed, not rebuilt.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.BackfillWatchlistTitleEmbed

  describe "after the table was renamed" do
    test "the flat columns are not present, so the backfill is a clean no-op" do
      refute BackfillWatchlistTitleEmbed.flat_columns_present?(Repo)
      assert :ok = BackfillWatchlistTitleEmbed.backfill(Repo)
    end
  end

  describe "column_present?/3" do
    test "reads the table's columns from PRAGMA table_info" do
      assert BackfillWatchlistTitleEmbed.column_present?(Repo, "title_intents", "tmdb_id")
      refute BackfillWatchlistTitleEmbed.column_present?(Repo, "title_intents", "year")
    end

    test "a table that no longer exists reports no columns, never raises" do
      refute BackfillWatchlistTitleEmbed.column_present?(Repo, "watchlist_items", "tmdb_id")
    end
  end
end
