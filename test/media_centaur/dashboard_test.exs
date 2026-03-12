defmodule MediaCentaur.DashboardTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Dashboard

  import MediaCentaur.TestFactory

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

  describe "fetch_recent_additions/0" do
    test "returns entities ordered newest-first, limited to 10" do
      entities =
        for i <- 1..12 do
          create_entity(%{name: "Entity #{i}"})
        end

      recent = Dashboard.fetch_recent_additions()

      assert length(recent) == 10

      expected_names = entities |> Enum.reverse() |> Enum.take(10) |> Enum.map(& &1.name)
      assert Enum.map(recent, & &1.name) == expected_names
    end

    test "returns empty list when no entities exist" do
      assert Dashboard.fetch_recent_additions() == []
    end
  end
end
