defmodule MediaCentaur.Library.EpisodesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.Episodes

  import MediaCentaur.TestFactory

  describe "ids_by_season_episode/1" do
    test "maps every episode of the series by its {season, episode} pair" do
      series = create_tv_series(%{name: "Sample Show"})
      season_one = create_season(%{tv_series_id: series.id, season_number: 1})
      season_two = create_season(%{tv_series_id: series.id, season_number: 2})
      first = create_episode(%{season_id: season_one.id, episode_number: 1, name: "One"})
      second = create_episode(%{season_id: season_two.id, episode_number: 3, name: "Three"})

      other = create_tv_series(%{name: "Other Show"})
      other_season = create_season(%{tv_series_id: other.id, season_number: 1})
      create_episode(%{season_id: other_season.id, episode_number: 1, name: "Elsewhere"})

      assert Episodes.ids_by_season_episode(series.id) == %{
               {1, 1} => first.id,
               {2, 3} => second.id
             }
    end

    test "is empty for a series with no episodes" do
      series = create_tv_series(%{name: "Sample Show"})
      assert Episodes.ids_by_season_episode(series.id) == %{}
    end
  end

  describe "last_season_episode/1" do
    test "returns the highest {season, episode} pair the series has" do
      series = create_tv_series(%{name: "Sample Show"})
      season_one = create_season(%{tv_series_id: series.id, season_number: 1})
      season_two = create_season(%{tv_series_id: series.id, season_number: 2})
      create_episode(%{season_id: season_one.id, episode_number: 9, name: "Nine"})
      create_episode(%{season_id: season_two.id, episode_number: 2, name: "Two"})
      create_episode(%{season_id: season_two.id, episode_number: 1, name: "One"})

      assert Episodes.last_season_episode(series.id) == {2, 2}
    end

    test "is nil for a series with no episodes" do
      series = create_tv_series(%{name: "Sample Show"})
      assert Episodes.last_season_episode(series.id) == nil
    end
  end
end
