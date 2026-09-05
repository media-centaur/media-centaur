defmodule MediaCentaur.Acquisition.Plans.DownloadScopeTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Plans.DownloadScope
  alias MediaCentaur.Acquisition.Targeting

  defp episode(season, number, opts \\ []) do
    %Targeting.Episode{
      season_number: season,
      episode_number: number,
      label: "S#{season}E#{number}",
      aired?: Keyword.get(opts, :aired?, true),
      in_library?: Keyword.get(opts, :in_library?, false),
      tracked?: Keyword.get(opts, :tracked?, false)
    }
  end

  defp selection(seasons) do
    %Targeting.Selection{tmdb_id: "42", title: "Sample Show", tracked?: false, seasons: seasons}
  end

  test "first_season is the lowest numbered season ≥ 1 with a pickable episode, specials skipped" do
    selection =
      selection([
        %Targeting.Season{season_number: 0, episodes: [episode(0, 1)]},
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1, in_library?: true), episode(1, 2)]},
        %Targeting.Season{season_number: 2, episodes: [episode(2, 1)]}
      ])

    assert DownloadScope.units(selection, :first_season) == [{1, 2}]
  end

  test "first_season moves past a season with nothing pickable" do
    selection =
      selection([
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1, tracked?: true)]},
        %Targeting.Season{season_number: 2, episodes: [episode(2, 1), episode(2, 2, aired?: false)]}
      ])

    assert DownloadScope.units(selection, :first_season) == [{2, 1}]
  end

  test "everything is the picker default: all aired, not in library, not tracked" do
    selection =
      selection([
        %Targeting.Season{season_number: 0, episodes: [episode(0, 1)]},
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1), episode(1, 2, in_library?: true)]},
        %Targeting.Season{season_number: 2, episodes: [episode(2, 1), episode(2, 2, aired?: false)]}
      ])

    assert DownloadScope.units(selection, :everything) == [{0, 1}, {1, 1}, {2, 1}]
  end

  test "an empty universe yields no units for either scope" do
    assert DownloadScope.units(selection([]), :first_season) == []
    assert DownloadScope.units(selection([]), :everything) == []
  end
end
