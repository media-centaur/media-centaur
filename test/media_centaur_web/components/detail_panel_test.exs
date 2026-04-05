defmodule MediaCentaurWeb.Components.DetailPanelTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.Components.DetailPanel

  describe "auto_expand_season/2" do
    test "expands season containing current episode" do
      season1 = build_season(%{season_number: 1, episodes: []})
      season2 = build_season(%{season_number: 2, episodes: []})
      entity = build_entity(%{type: :tv_series, seasons: [season1, season2]})

      progress = %{
        current_episode: %{season: 2, episode: 5},
        episode_position_seconds: 100.0,
        episode_duration_seconds: 2700.0,
        episodes_completed: 4,
        episodes_total: 10
      }

      assert DetailPanel.auto_expand_season(entity, progress) == MapSet.new([2])
    end

    test "falls back to season 1 when current season not found in entity" do
      season1 = build_season(%{season_number: 1, episodes: []})
      entity = build_entity(%{type: :tv_series, seasons: [season1]})

      progress = %{
        current_episode: %{season: 99, episode: 1},
        episode_position_seconds: 0.0,
        episode_duration_seconds: 0.0,
        episodes_completed: 0,
        episodes_total: 0
      }

      assert DetailPanel.auto_expand_season(entity, progress) == MapSet.new([1])
    end

    test "expands season 1 when no progress" do
      season = build_season(%{season_number: 1, episodes: []})
      entity = build_entity(%{type: :tv_series, seasons: [season]})

      assert DetailPanel.auto_expand_season(entity, nil) == MapSet.new([1])
    end

    test "expands first available season when season 1 does not exist" do
      season3 = build_season(%{season_number: 3, episodes: []})
      entity = build_entity(%{type: :tv_series, seasons: [season3]})

      assert DetailPanel.auto_expand_season(entity, nil) == MapSet.new([3])
    end

    test "returns empty set for empty seasons list" do
      entity = build_entity(%{type: :tv_series, seasons: []})

      assert DetailPanel.auto_expand_season(entity, nil) == MapSet.new()
    end

    test "returns empty set for non-tv entity" do
      entity = build_entity(%{type: :movie})

      assert DetailPanel.auto_expand_season(entity, nil) == MapSet.new()
    end
  end

  # --- overall_progress_percent/2 ---

  describe "overall_progress_percent/2" do
    test "returns 0 for nil progress" do
      assert DetailPanel.overall_progress_percent(nil, build_entity()) == 0
    end

    test "computes episode-based percentage for tv_series" do
      progress = %{episodes_completed: 3, episodes_total: 10}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.overall_progress_percent(progress, entity) == 30
    end

    test "computes episode-based percentage for movie_series" do
      progress = %{episodes_completed: 2, episodes_total: 3}
      entity = build_entity(%{type: :movie_series})

      assert DetailPanel.overall_progress_percent(progress, entity) == 67
    end

    test "returns 0 when episodes_total is 0 for series" do
      progress = %{episodes_completed: 0, episodes_total: 0}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.overall_progress_percent(progress, entity) == 0
    end

    test "computes position-based percentage for standalone movie" do
      progress = %{
        episode_position_seconds: 1800.0,
        episode_duration_seconds: 3600.0,
        episodes_completed: 0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.overall_progress_percent(progress, entity) == 50
    end

    test "returns 100 when completed but no duration for movie" do
      progress = %{
        episode_position_seconds: 0.0,
        episode_duration_seconds: 0.0,
        episodes_completed: 1
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.overall_progress_percent(progress, entity) == 100
    end

    test "caps at 100" do
      progress = %{episodes_completed: 11, episodes_total: 10}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.overall_progress_percent(progress, entity) == 100
    end
  end

  # --- progress_remaining_text/2 ---

  describe "progress_remaining_text/2" do
    test "returns nil for nil progress" do
      assert DetailPanel.progress_remaining_text(nil, build_entity()) == nil
    end

    test "returns Watched when all episodes complete for tv_series" do
      progress = %{episodes_total: 10, episodes_completed: 10}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.progress_remaining_text(progress, entity) == "Watched"
    end

    test "returns singular episode count for tv_series" do
      progress = %{episodes_total: 10, episodes_completed: 9}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.progress_remaining_text(progress, entity) == "1 episode left"
    end

    test "returns plural episode count for tv_series" do
      progress = %{episodes_total: 10, episodes_completed: 7}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.progress_remaining_text(progress, entity) == "3 episodes left"
    end

    test "returns movie count for movie_series" do
      progress = %{episodes_total: 3, episodes_completed: 1}
      entity = build_entity(%{type: :movie_series})

      assert DetailPanel.progress_remaining_text(progress, entity) == "2 movies left"
    end

    test "returns Watched for completed standalone movie" do
      progress = %{
        episodes_completed: 1,
        episode_duration_seconds: 0.0,
        episode_position_seconds: 0.0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.progress_remaining_text(progress, entity) == "Watched"
    end

    test "returns time remaining for in-progress standalone movie" do
      progress = %{
        episodes_completed: 0,
        episode_duration_seconds: 7200.0,
        episode_position_seconds: 3600.0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.progress_remaining_text(progress, entity) == "1h remaining"
    end
  end

  # --- episode_state/1 ---

  describe "episode_state/1" do
    test "returns :unwatched for nil" do
      assert DetailPanel.episode_state(nil) == :unwatched
    end

    test "returns :watched when completed" do
      progress = %{completed: true, position_seconds: 2700.0}
      assert DetailPanel.episode_state(progress) == :watched
    end

    test "returns :current when has position" do
      progress = %{completed: false, position_seconds: 100.0}
      assert DetailPanel.episode_state(progress) == :current
    end

    test "returns :unwatched when no position and not completed" do
      progress = %{completed: false, position_seconds: 0.0}
      assert DetailPanel.episode_state(progress) == :unwatched
    end
  end

  # --- episode_row_class/2 ---

  describe "episode_row_class/2" do
    test "returns primary highlight when resume target" do
      assert DetailPanel.episode_row_class(:watched, true) ==
               "border-l-2 border-primary bg-primary/5"
    end

    test "returns opacity for watched" do
      assert DetailPanel.episode_row_class(:watched, false) == "opacity-60"
    end

    test "returns info bg for current" do
      assert DetailPanel.episode_row_class(:current, false) == "bg-info/5"
    end

    test "returns empty for unwatched" do
      assert DetailPanel.episode_row_class(:unwatched, false) == ""
    end
  end

  # --- progress_percent/1 ---

  describe "progress_percent/1" do
    test "computes percentage from position and duration" do
      assert DetailPanel.progress_percent(%{position_seconds: 900, duration_seconds: 3600}) == 25
    end

    test "caps at 100" do
      assert DetailPanel.progress_percent(%{position_seconds: 4000, duration_seconds: 3600}) ==
               100
    end

    test "returns 0 for nil" do
      assert DetailPanel.progress_percent(nil) == 0
    end

    test "returns 0 when duration is 0" do
      assert DetailPanel.progress_percent(%{position_seconds: 100, duration_seconds: 0}) == 0
    end
  end

  # --- format_file_size/1 ---

  describe "format_file_size/1" do
    test "formats gigabytes" do
      assert DetailPanel.format_file_size(2_147_483_648) == "2.0 GB"
    end

    test "formats megabytes" do
      assert DetailPanel.format_file_size(10_485_760) == "10.0 MB"
    end

    test "formats kilobytes" do
      assert DetailPanel.format_file_size(2048) == "2.0 KB"
    end

    test "formats bytes" do
      assert DetailPanel.format_file_size(512) == "512 B"
    end
  end

  # --- file_summary/2 ---

  describe "file_summary/2" do
    test "formats singular file count" do
      assert DetailPanel.file_summary(1, 1_073_741_824) == "1 file, 1.0 GB"
    end

    test "formats plural file count" do
      assert DetailPanel.file_summary(3, 3_145_728) == "3 files, 3.0 MB"
    end
  end

  # --- build_episode_list/2 ---

  describe "build_episode_list/2" do
    test "maps episodes by number, filling gaps" do
      episode1 = build_episode(%{episode_number: 1})
      episode3 = build_episode(%{episode_number: 3})

      result = DetailPanel.build_episode_list([episode1, episode3], 3)

      assert [{:episode, ^episode1}, {:missing, 2}, {:episode, ^episode3}] = result
    end

    test "returns empty list when no episodes and zero count" do
      assert DetailPanel.build_episode_list([], 0) == []
    end

    test "extends to number_of_episodes when higher than max episode" do
      episode = build_episode(%{episode_number: 1})
      result = DetailPanel.build_episode_list([episode], 3)

      assert length(result) == 3
      assert {:missing, 2} = Enum.at(result, 1)
      assert {:missing, 3} = Enum.at(result, 2)
    end
  end

  # --- count_watched_episodes/2 ---

  describe "count_watched_episodes/2" do
    test "counts completed episodes in a season" do
      episode1 = build_episode(%{episode_number: 1})
      episode2 = build_episode(%{episode_number: 2})
      episode3 = build_episode(%{episode_number: 3})
      season = build_season(%{season_number: 1, episodes: [episode1, episode2, episode3]})

      progress_by_key = %{
        episode1.id => %{completed: true},
        episode3.id => %{completed: true},
        episode2.id => %{completed: false}
      }

      assert DetailPanel.count_watched_episodes(season, progress_by_key) == 2
    end

    test "returns 0 when no progress" do
      episode = build_episode(%{episode_number: 1})
      season = build_season(%{season_number: 1, episodes: [episode]})

      assert DetailPanel.count_watched_episodes(season, %{}) == 0
    end
  end
end
