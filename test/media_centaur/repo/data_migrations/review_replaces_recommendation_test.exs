defmodule MediaCentaur.Repo.DataMigrations.ReviewReplacesRecommendationTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.ReviewReplacesRecommendation
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  setup do
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  defp title(id), do: Title.new!(%{tmdb_id: id, media_type: :movie, name: "Sample Movie #{id}"})

  # The schema no longer admits the retired kind, so the legacy state is
  # written the way the old app left it: straight into the column.
  defp make_recommendation!(%Activity{id: id}) do
    Repo.query!("UPDATE activities SET kind = 'recommendation' WHERE id = ?", [id])
    :ok
  end

  defp kinds do
    %{rows: rows} = Repo.query!("SELECT kind FROM activities ORDER BY kind", [])
    List.flatten(rows)
  end

  describe "sweep/1" do
    test "removes stored recommendation rows and leaves every other kind" do
      {:ok, legacy} = Activities.review(title(1), :like, "old words")
      make_recommendation!(legacy)
      {:ok, _review} = Activities.review(title(2), :love, nil)
      {:ok, _listing} = Activities.listing(title(3))

      assert :ok = ReviewReplacesRecommendation.sweep(Repo)

      assert kinds() == ["listing", "review"]
    end

    test "is idempotent and a no-op on a clean database" do
      assert :ok = ReviewReplacesRecommendation.sweep(Repo)
      assert :ok = ReviewReplacesRecommendation.sweep(Repo)
      assert kinds() == []
    end
  end
end
