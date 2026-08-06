defmodule MediaCentaur.Acquisition.Pursuits.ReconciliationCompletionTest do
  @moduledoc """
  End-to-end guard for the reconciliation-engine campaign's completion
  convergence (Phase B): a pursuit for a canonical episode completes when
  that episode becomes *present on the spine*, regardless of how the
  release labelled itself.

  The two halves are unit-tested elsewhere — `Reconciliation.confirm`
  links a diverted file to its canonical episode (`confirm_test.exs`), and
  `LibraryReconciler` satisfies an episode-identity unit only on its own
  episode's presence (`library_reconciler_test.exs`, ADR-058). This pins
  the *seam between them*: a split-cour file labelled `S02E01` that a
  pursuit wants as canonical `S01E03` does not complete the pursuit while
  it sits in the mapping queue, and does complete once the user confirms
  the mapping. That is the wedge-bug class (a pursuit that never completes
  because the release's numbering disagrees with TMDB's) retired at the
  seam, not just in each half.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{LibraryReconciler, Pursuit}
  alias MediaCentaur.Library
  alias MediaCentaur.Reconciliation
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

  # Show TMDB-numbers as one season; E1–E2 are present (the earlier cour),
  # E3 is the wanted later-cour episode the release labels `S02E01`.
  defp seed_show do
    series = create_tv_series(%{name: "Sample Show", tmdb_id: "42"})
    season = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})

    for episode_number <- [1, 2] do
      episode = create_episode(%{season_id: season.id, episode_number: episode_number, name: "Ep"})
      playable_item = create_playable_item_for_episode(episode)

      create_linked_file(%{
        playable_item_id: playable_item.id,
        file_path: "/media/s/E#{episode_number}.mkv"
      })
    end

    TmdbStubs.stub_routes([
      {"/tv/42/season/1",
       TmdbStubs.season_detail(%{
         "season_number" => 1,
         "episodes" => [
           %{"episode_number" => 1, "name" => "Alpha"},
           %{"episode_number" => 2, "name" => "Beta"},
           %{"episode_number" => 3, "name" => "Gamma"}
         ]
       })},
      {"/tv/42", TmdbStubs.tv_detail(%{"id" => 42, "seasons" => [%{"season_number" => 1}]})}
    ])

    series
  end

  test "a diverted cour file completes the pursuit only after its mapping is confirmed" do
    seed_show()

    {pursuit, _target} =
      create_pursuit_with_target(%{
        recipe_type: "tmdb",
        tmdb_id: "42",
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 1,
        episode_number: 3,
        status: "acquired"
      })

    # The release lands labelled S02E01 and Phase A diverts it to the
    # mapping queue — it is NOT linked to a canonical episode yet.
    {:ok, _awaiting} =
      Reconciliation.divert(%{
        file_path: "/media/s/S02E01.mkv",
        media_dir: "/media/s",
        tmdb_id: 42,
        claimed_season: 2,
        claimed_episode: 1,
        claimed_title: "Gamma"
      })

    # E3 is not present, so completion must not fire — even though the
    # file for it has physically landed. (Release numbering must not
    # satisfy; only canonical presence does.)
    assert :ok = LibraryReconciler.reconcile_active()

    assert Repo.get!(Pursuit, pursuit.id).state == "active",
           "an unmapped cour file must not complete the pursuit"

    assert Library.ExternalIds.find_present_episode("42", 1, 3) == :not_found

    # The user confirms the mapping in /reconcile: the file links to
    # canonical E3, which now exists and is present on the spine.
    review = Reconciliation.resolve_show(42)
    assert {:ok, %{linked: 1, failed: 0}} = Reconciliation.confirm_recommended(review)
    assert {:ok, "/media/s/S02E01.mkv"} = Library.ExternalIds.find_present_episode("42", 1, 3)

    # Now completion fires by canonical presence.
    assert :ok = LibraryReconciler.reconcile_active()
    assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
  end
end
