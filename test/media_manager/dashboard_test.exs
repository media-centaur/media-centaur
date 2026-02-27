defmodule MediaManager.DashboardTest do
  use MediaManager.DataCase, async: false

  alias MediaManager.Dashboard

  import MediaManager.TestFactory

  describe "fetch_library_stats/0" do
    test "counts episodes" do
      entity = create_entity(%{type: :tv_series, name: "Test Show"})
      season = create_season(%{season_number: 1, entity_id: entity.id})
      create_episode(%{episode_number: 1, season_id: season.id})
      create_episode(%{episode_number: 2, season_id: season.id})

      stats = Dashboard.fetch_library_stats()

      assert stats.episodes == 2
    end

    test "returns zero episodes when none exist" do
      stats = Dashboard.fetch_library_stats()

      assert stats.episodes == 0
    end
  end
end
