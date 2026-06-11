defmodule MediaCentaur.Acquisition.ViewModels.PlanBoardOverlapTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.PlanBoard

  defp release(guid, title, scope_label, swap_unit_id) do
    %PlanBoard.Release{
      guid: guid,
      title: title,
      scope_label: scope_label,
      units_count: 1,
      swap_unit_id: swap_unit_id
    }
  end

  test "a broad pack physically containing another release's claimed units is flagged" do
    releases = [
      release("pack-1-9", "Sample.Show.S01-09.COMPLETE.1080p.WEB-DL", "Seasons 1–9 pack", "unit-a"),
      release("pack-s1", "Sample.Show.S01.1080p.WEBRip.x265", "Season 1 pack", "unit-b")
    ]

    claims = %{
      "pack-1-9" => for(season <- 2..9, episode <- 1..3, do: {season, episode}),
      "pack-s1" => [{1, 1}, {1, 2}, {1, 3}]
    }

    assert [overlap] = PlanBoard.overlaps(releases, claims)
    assert overlap.exclude_guid == "pack-1-9"
    assert overlap.exclude_unit_id == "unit-a"
    assert overlap.description =~ "Seasons 1–9 pack also contains 3 episodes"
    assert overlap.description =~ "download twice"
    assert overlap.action_label == "Remove it & re-solve"
  end

  test "disjoint releases produce no overlaps" do
    releases = [
      release("pack-s1", "Sample.Show.S01.COMPLETE.1080p", "Season 1 pack", "unit-a"),
      release("pack-s2", "Sample.Show.S02.COMPLETE.1080p", "Season 2 pack", "unit-b")
    ]

    claims = %{
      "pack-s1" => [{1, 1}, {1, 2}],
      "pack-s2" => [{2, 1}, {2, 2}]
    }

    assert PlanBoard.overlaps(releases, claims) == []
  end

  test "a single shadowed episode reads grammatically" do
    releases = [
      release("pack-s1", "Sample.Show.S01.COMPLETE.1080p", "Season 1 pack", "unit-a"),
      release("e1-uhd", "Sample.Show.S01E01.2160p.WEB-DL.x265", "S01E01", "unit-b")
    ]

    claims = %{
      "pack-s1" => [{1, 2}, {1, 3}],
      "e1-uhd" => [{1, 1}]
    }

    assert [overlap] = PlanBoard.overlaps(releases, claims)
    assert overlap.exclude_guid == "pack-s1"
    assert overlap.description =~ "Season 1 pack also contains 1 episode assigned"
  end

  test "an unparseable title covers nothing and is never flagged" do
    releases = [
      release("weird", "Sample Show Bundle", nil, "unit-a"),
      release("pack-s1", "Sample.Show.S01.COMPLETE.1080p", "Season 1 pack", "unit-b")
    ]

    claims = %{
      "weird" => [{2, 1}],
      "pack-s1" => [{1, 1}]
    }

    assert PlanBoard.overlaps(releases, claims) == []
  end

  test "movie boards (nil season/episode units) produce no overlaps" do
    releases = [release("movie", "Sample.Movie.2010.1080p.BluRay", nil, "unit-a")]
    claims = %{"movie" => [{nil, nil}]}

    assert PlanBoard.overlaps(releases, claims) == []
  end
end
