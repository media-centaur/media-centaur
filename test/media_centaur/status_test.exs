defmodule MediaCentaur.StatusTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Status

  import MediaCentaur.TestFactory

  describe "library_stats/0" do
    test "counts episodes" do
      tv_series = create_entity(%{type: :tv_series, name: "Test Show"})
      season = create_season(%{season_number: 1, tv_series_id: tv_series.id})
      create_episode(%{episode_number: 1, season_id: season.id})
      create_episode(%{episode_number: 2, season_id: season.id})

      stats = Status.library_stats()

      assert stats.episodes == 2
    end

    test "returns zero episodes when none exist" do
      stats = Status.library_stats()

      assert stats.episodes == 0
    end
  end
end
