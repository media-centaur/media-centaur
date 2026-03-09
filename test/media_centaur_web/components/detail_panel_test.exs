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
end
