defmodule MediaCentaur.ReleaseTracking.HadTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.{Had, Item, Release}

  defp item(season, episode),
    do: %Item{media_type: :tv_series, last_library_season: season, last_library_episode: episode}

  describe "point/2 — the later of the library watermark and the caught-up point" do
    test "no point: the watermark; no watermark: {0, 0}" do
      assert Had.point(item(2, 13), nil) == {2, 13}
      assert Had.point(%Item{media_type: :tv_series}, nil) == {0, 0}
    end

    test "whichever is later wins, season before episode" do
      assert Had.point(item(2, 13), {1, 28}) == {2, 13}
      assert Had.point(item(1, 4), {1, 28}) == {1, 28}
      assert Had.point(item(0, 0), {3, 1}) == {3, 1}
    end
  end

  describe "had?/2" do
    test "in the library, whatever the point" do
      assert Had.had?(%Release{in_library: true, season_number: 9, episode_number: 9}, {0, 0})
    end

    test "a series release at or before the point; after it, not had" do
      assert Had.had?(%Release{season_number: 1, episode_number: 28}, {1, 28})
      assert Had.had?(%Release{season_number: 1, episode_number: 3}, {2, 1})
      refute Had.had?(%Release{season_number: 1, episode_number: 29}, {1, 28})
      refute Had.had?(%Release{season_number: 2, episode_number: 1}, {1, 28})
    end

    test "a movie row has no position: had only through the library" do
      refute Had.had?(%Release{season_number: nil, episode_number: nil, release_type: "digital"}, {5, 5})
    end
  end
end
