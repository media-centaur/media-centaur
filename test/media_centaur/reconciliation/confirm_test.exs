defmodule MediaCentaur.Reconciliation.ConfirmTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Reconciliation
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

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

  test "confirming the recommendation links the file to the canonical episode, creating it from the spine" do
    series = seed_show()

    {:ok, awaiting} =
      Reconciliation.divert(%{
        file_path: "/media/s/S02E01.mkv",
        media_dir: "/media/s",
        tmdb_id: 42,
        claimed_season: 2,
        claimed_episode: 1,
        claimed_title: "Gamma"
      })

    review = Reconciliation.resolve_show(42)

    assert {:ok, summary} = Reconciliation.confirm_recommended(review)
    assert summary.linked == 1
    assert summary.failed == 0

    # The previously-missing E3 now exists with its canonical title and a file.
    episode = Library.Episodes.find_by_season_episode(series.id, 1, 3)
    assert episode.name == "Gamma"
    assert {:ok, "/media/s/S02E01.mkv"} = Library.ExternalIds.find_present_episode("42", 1, 3)

    # The awaiting record is resolved and off the pending queue.
    assert Reconciliation.list_awaiting() == []
    refute awaiting.id in Enum.map(Reconciliation.list_awaiting(), & &1.id)
  end

  test "confirm/2 honors explicit per-file targets (override / partial-accept)" do
    seed_show()

    {:ok, a} =
      Reconciliation.divert(%{
        file_path: "/media/s/fileA.mkv",
        media_dir: "/media/s",
        tmdb_id: 42,
        claimed_season: 2,
        claimed_episode: 1,
        claimed_title: nil
      })

    {:ok, _b} =
      Reconciliation.divert(%{
        file_path: "/media/s/fileB.mkv",
        media_dir: "/media/s",
        tmdb_id: 42,
        claimed_season: 2,
        claimed_episode: 2,
        claimed_title: nil
      })

    review = Reconciliation.resolve_show(42)

    # Confirm only file A, overriding it onto E3; leave B for later.
    assert {:ok, summary} = Reconciliation.confirm(review, %{a.id => {1, 3}})
    assert summary.linked == 1

    assert {:ok, _} = Library.ExternalIds.find_present_episode("42", 1, 3)
    # B remains pending.
    assert Enum.map(Reconciliation.list_awaiting(), & &1.claimed_episode) == [2]
  end

  test "confirm refuses when the series is not in the library" do
    # No library series for tmdb 555; spine fetch 404s.
    TmdbStubs.stub_tmdb_error("/tv/555", 404)

    {:ok, _} =
      Reconciliation.divert(%{
        file_path: "/media/x/f.mkv",
        media_dir: "/media/x",
        tmdb_id: 555,
        claimed_season: 2,
        claimed_episode: 1
      })

    review = Reconciliation.resolve_show(555)

    assert {:error, :series_not_in_library} = Reconciliation.confirm_recommended(review)
  end
end
