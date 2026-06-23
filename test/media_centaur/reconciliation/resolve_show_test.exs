defmodule MediaCentaur.Reconciliation.ResolveShowTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Reconciliation
  alias MediaCentaur.Reconciliation.ShowReview
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

  # Library series carrying TMDB id 42, with E1/E2 present (linked files) and
  # E3 the gap. TMDB (stubbed) is the spine source — three episodes.
  defp seed_show do
    series = create_tv_series(%{name: "Sample Show", tmdb_id: "42"})
    season = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})

    for episode_number <- [1, 2] do
      episode =
        create_episode(%{season_id: season.id, episode_number: episode_number, name: "Ep"})

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

  test "resolves an awaiting file onto the canonical gap" do
    seed_show()

    {:ok, awaiting} =
      Reconciliation.divert(%{
        file_path: "/media/s/S02E01.mkv",
        media_dir: "/media/s",
        tmdb_id: 42,
        claimed_season: 2,
        claimed_episode: 1,
        claimed_title: "Gamma"
      })

    %ShowReview{} = review = Reconciliation.resolve_show(42)

    assert review.series_title == "Sample Show"
    assert Enum.map(review.awaiting_files, & &1.id) == [awaiting.id]
    # Spine is TMDB's three episodes; E1/E2 present, E3 the gap.
    assert length(review.spine) == 3
    # The lone file maps onto E3 (title "Gamma" + the only gap node agree).
    assert [placement] = review.resolution.recommended.placements
    assert placement.artifact_id == awaiting.id
    assert {placement.season, placement.episode} == {1, 3}
  end

  test "returns an empty-but-valid review when the show is unknown to the library" do
    TmdbStubs.stub_tmdb_error("/tv/777", 404)

    review = Reconciliation.resolve_show(777)

    assert review.spine == []
    assert review.resolution.recommended == nil
    assert review.awaiting_files == []
  end
end
