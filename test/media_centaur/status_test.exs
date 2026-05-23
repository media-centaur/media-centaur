defmodule MediaCentaur.StatusTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Status

  import MediaCentaur.TestFactory

  describe "fetch_library_stats/0" do
    test "counts episodes" do
      tv_series = create_entity(%{type: :tv_series, name: "Test Show"})
      season = create_season(%{season_number: 1, tv_series_id: tv_series.id})
      create_episode(%{episode_number: 1, season_id: season.id})
      create_episode(%{episode_number: 2, season_id: season.id})

      stats = Status.fetch_library_stats()

      assert stats.episodes == 2
    end

    test "returns zero episodes when none exist" do
      stats = Status.fetch_library_stats()

      assert stats.episodes == 0
    end
  end

  describe "fetch_recent_changes/0" do
    test "returns change entries ordered newest-first" do
      alias MediaCentaur.Library.ChangeLog

      movie_a = create_entity(%{name: "First Movie"})
      ChangeLog.record_addition(movie_a, :movie)
      movie_b = create_entity(%{name: "Second Movie"})
      ChangeLog.record_addition(movie_b, :movie)

      changes = Status.fetch_recent_changes()

      assert length(changes) == 2
      assert hd(changes).entity_name == "Second Movie"
    end

    test "includes both additions and removals" do
      alias MediaCentaur.Library.ChangeLog

      movie = create_entity(%{name: "Test Movie"})
      ChangeLog.record_addition(movie, :movie)
      ChangeLog.record_removal(%{id: movie.id, name: movie.name, type: :movie})

      changes = Status.fetch_recent_changes()

      kinds = Enum.map(changes, & &1.kind)
      assert :added in kinds
      assert :removed in kinds
    end

    test "returns empty list when no changes exist" do
      assert Status.fetch_recent_changes() == []
    end
  end
end
