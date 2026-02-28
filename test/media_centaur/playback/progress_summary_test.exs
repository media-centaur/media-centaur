defmodule MediaCentaur.Playback.ProgressSummaryTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaur.Playback.ProgressSummary

  describe "no progress" do
    test "empty list returns nil" do
      entity = build_entity(%{type: :movie, name: "No Progress"})
      assert ProgressSummary.compute(entity, []) == nil
    end
  end

  describe "Movie" do
    test "partial progress returns position/duration, completed 0, total 1" do
      entity = build_entity(%{type: :movie, name: "Movie"})

      progress = [
        build_progress(%{
          position_seconds: 600.0,
          duration_seconds: 7200.0,
          completed: false
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == nil
      assert result.episode_position_seconds == 600.0
      assert result.episode_duration_seconds == 7200.0
      assert result.episodes_completed == 0
      assert result.episodes_total == 1
    end

    test "completed progress returns completed 1" do
      entity = build_entity(%{type: :movie, name: "Done Movie"})

      progress = [
        build_progress(%{
          position_seconds: 7000.0,
          duration_seconds: 7200.0,
          completed: true
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.episodes_completed == 1
      assert result.episodes_total == 1
    end
  end

  describe "TVSeries" do
    test "no progress on episodes returns current_episode as first, position 0" do
      entity = build_tv_entity_with_episodes()

      # A progress record exists but is not completed, for S01E01
      progress = [
        build_progress(%{
          season_number: 1,
          episode_number: 1,
          position_seconds: 0.0,
          duration_seconds: 2400.0,
          completed: false
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 1}
      assert result.episode_position_seconds == 0.0
      assert result.episodes_completed == 0
      assert result.episodes_total == 3
    end

    test "partial progress on E02 makes current E02" do
      entity = build_tv_entity_with_episodes()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          season_number: 1,
          episode_number: 1,
          position_seconds: 2400.0,
          duration_seconds: 2400.0,
          completed: true,
          last_watched_at: DateTime.add(now, -60, :second)
        }),
        build_progress(%{
          season_number: 1,
          episode_number: 2,
          position_seconds: 600.0,
          duration_seconds: 2400.0,
          completed: false,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 2}
      assert result.episode_position_seconds == 600.0
      assert result.episodes_completed == 1
    end

    test "completed E01 advances to E02" do
      entity = build_tv_entity_with_episodes()

      progress = [
        build_progress(%{
          season_number: 1,
          episode_number: 1,
          position_seconds: 2400.0,
          duration_seconds: 2400.0,
          completed: true,
          last_watched_at: DateTime.utc_now()
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 2}
      assert result.episode_position_seconds == 0.0
      assert result.episodes_completed == 1
    end

    test "all completed stays on last episode" do
      entity = build_tv_entity_with_episodes()

      now = DateTime.utc_now()

      progress = [
        build_progress(%{
          season_number: 1,
          episode_number: 1,
          completed: true,
          last_watched_at: DateTime.add(now, -120, :second)
        }),
        build_progress(%{
          season_number: 1,
          episode_number: 2,
          completed: true,
          last_watched_at: DateTime.add(now, -60, :second)
        }),
        build_progress(%{
          season_number: 1,
          episode_number: 3,
          completed: true,
          last_watched_at: now
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      assert result.current_episode == %{season: 1, episode: 3}
      assert result.episodes_completed == 3
      assert result.episodes_total == 3
    end

    test "episodes without content_url are skipped from total" do
      episode_a = build_episode(%{episode_number: 1, name: "E1", content_url: "/ep1.mkv"})
      episode_b = build_episode(%{episode_number: 2, name: "E2", content_url: nil})
      episode_c = build_episode(%{episode_number: 3, name: "E3", content_url: "/ep3.mkv"})
      season = build_season(%{season_number: 1, episodes: [episode_a, episode_b, episode_c]})

      entity =
        build_entity(%{
          type: :tv_series,
          name: "Partial Show",
          seasons: [season]
        })

      progress = [
        build_progress(%{
          season_number: 1,
          episode_number: 1,
          position_seconds: 0.0,
          duration_seconds: 2400.0,
          completed: false
        })
      ]

      result = ProgressSummary.compute(entity, progress)

      # Only 2 episodes have content_url
      assert result.episodes_total == 2
    end
  end

  # Builds a TV entity with 3 episodes, all with content_url set
  defp build_tv_entity_with_episodes do
    episode_a = build_episode(%{episode_number: 1, name: "Pilot", content_url: "/s01e01.mkv"})
    episode_b = build_episode(%{episode_number: 2, name: "Second", content_url: "/s01e02.mkv"})
    episode_c = build_episode(%{episode_number: 3, name: "Third", content_url: "/s01e03.mkv"})
    season = build_season(%{season_number: 1, episodes: [episode_a, episode_b, episode_c]})

    build_entity(%{
      type: :tv_series,
      name: "Test Show",
      seasons: [season]
    })
  end
end
