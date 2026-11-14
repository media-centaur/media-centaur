defmodule MediaCentaur.Playback.ResumeTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.Resume

  # The rest of this file moved to
  # `test/media_centaur/library/title_progress_regression_test.exs` when
  # `Library.TitleProgress` replaced `Resume` as the Play target. These two
  # stay with `Resume` until the owner decides them: restated in the three
  # facts (the completed final episode becomes the series watch position),
  # the new rule reads both series as complete, which neither expectation
  # allows, and neither is one of the two changes the design names.

  # Helper to build a minimal entity map
  defp tv_series(seasons) do
    %{type: :tv_series, content_url: nil, seasons: seasons, movies: nil}
  end

  defp season(number, episodes) do
    %{season_number: number, episodes: episodes}
  end

  defp episode(number, url) do
    %{id: Ecto.UUID.generate(), episode_number: number, content_url: url}
  end

  # Library Schema v2 Phase 2 Task C — WatchProgress is keyed by a
  # single `playable_item_id`. `ProgressRecords.list_for_container/3`
  # at runtime synthesises `:playable_item` carrying the
  # `(container_type, container_id)` discriminator; we mirror that
  # shape here so `Resume.resolve/2` works against plain fixtures.
  defp progress(opts) do
    playable_item =
      cond do
        episode_id = Keyword.get(opts, :episode_id) ->
          %{container_type: :episode, container_id: episode_id}

        movie_id = Keyword.get(opts, :movie_id) ->
          %{container_type: :movie, container_id: movie_id}

        true ->
          nil
      end

    %{
      playable_item: playable_item,
      position_seconds: Keyword.get(opts, :position, 0.0),
      duration_seconds: Keyword.get(opts, :duration, 0.0),
      completed: Keyword.get(opts, :completed, false),
      last_watched_at: Keyword.get(opts, :last_watched_at, ~U[2026-01-01 00:00:00Z])
    }
  end

  describe "TVSeries" do
    test "most-recent completed is the last item but earlier episodes unwatched → play first unwatched" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      ep3 = episode(3, "/tv/show/S01E03.mkv")
      entity = tv_series([season(1, [ep1, ep2, ep3])])

      records = [
        progress(
          episode_id: ep3.id,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:play_next, "/tv/show/S01E01.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end

    test "most-recent completed is last item but a partial earlier episode exists → play next unwatched (not restart)" do
      ep1 = episode(1, "/tv/show/S01E01.mkv")
      ep2 = episode(2, "/tv/show/S01E02.mkv")
      ep3 = episode(3, "/tv/show/S01E03.mkv")
      entity = tv_series([season(1, [ep1, ep2, ep3])])

      records = [
        progress(
          episode_id: ep1.id,
          position: 200.0,
          duration: 1800.0,
          completed: false,
          last_watched_at: ~U[2026-01-14 20:00:00Z]
        ),
        progress(
          episode_id: ep3.id,
          completed: true,
          last_watched_at: ~U[2026-01-15 20:00:00Z]
        )
      ]

      assert {:play_next, "/tv/show/S01E02.mkv", position} = Resume.resolve(entity, records)
      assert position == 0.0
    end
  end
end
