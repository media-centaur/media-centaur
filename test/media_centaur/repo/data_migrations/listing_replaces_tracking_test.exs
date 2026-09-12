defmodule MediaCentaur.Repo.DataMigrations.ListingReplacesTrackingTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.ListingReplacesTracking
  alias MediaCentaur.Settings
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  setup do
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  defp title(id), do: Title.new!(%{tmdb_id: id, media_type: :movie, name: "Sample Movie #{id}"})

  # The schema no longer admits the retired kind, so the legacy state is
  # written the way the old app left it: straight into the column.
  defp make_tracking!(%Activity{id: id}) do
    Repo.query!("UPDATE activities SET kind = 'tracking' WHERE id = ?", [id])
    :ok
  end

  defp kinds do
    %{rows: rows} = Repo.query!("SELECT kind FROM activities ORDER BY kind", [])
    List.flatten(rows)
  end

  describe "sweep/1" do
    test "removes stored tracking rows and the share_tracking setting, leaving the rest" do
      {:ok, legacy} = Activities.listing(title(1))
      make_tracking!(legacy)
      {:ok, _listing} = Activities.listing(title(2))
      {:ok, _review} = Activities.review(title(3), :like, nil)
      {:ok, _} = Settings.find_or_create_entry(%{key: "share_tracking", value: %{"enabled" => true}})
      {:ok, _} = Settings.find_or_create_entry(%{key: "share_watched", value: %{"enabled" => true}})

      assert :ok = ListingReplacesTracking.sweep(Repo)

      assert kinds() == ["listing", "review"]
      assert Settings.get_by_key("share_tracking") == nil
      assert %{value: %{"enabled" => true}} = Settings.get_by_key("share_watched")
    end

    test "is idempotent and a no-op on a clean database" do
      assert :ok = ListingReplacesTracking.sweep(Repo)
      assert :ok = ListingReplacesTracking.sweep(Repo)
      assert kinds() == []
    end
  end
end
