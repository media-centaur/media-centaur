defmodule MediaCentaur.Library.PresentEpisodeKeysTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library

  import MediaCentaur.TestFactory

  describe "present_episode_keys/1" do
    test "returns {season, episode} pairs that have a linked file" do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})

      linked = create_episode(%{season_id: season.id, episode_number: 1, name: "Alpha"})
      _unlinked = create_episode(%{season_id: season.id, episode_number: 2, name: "Beta"})

      playable_item = create_playable_item_for_episode(linked)
      create_linked_file(%{playable_item_id: playable_item.id, file_path: "/media/sample/E01.mkv"})

      assert Library.ExternalIds.present_episode_keys(series.id) == MapSet.new([{1, 1}])
    end

    test "returns an empty set when the series has no linked files" do
      series = create_tv_series(%{name: "Sample Show"})
      season = create_season(%{tv_series_id: series.id, season_number: 1, name: "Season 1"})
      create_episode(%{season_id: season.id, episode_number: 1, name: "Alpha"})

      assert Library.ExternalIds.present_episode_keys(series.id) == MapSet.new()
    end
  end
end
