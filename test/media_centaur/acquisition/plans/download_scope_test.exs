defmodule MediaCentaur.Acquisition.Plans.DownloadScopeTest do
  use MediaCentaur.Case, async: true

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

  test "first_missing_season is the lowest numbered season ≥ 1 with a pickable episode, specials skipped" do
    selection =
      selection([
        %Targeting.Season{season_number: 0, episodes: [episode(0, 1)]},
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1, in_library?: true), episode(1, 2)]},
        %Targeting.Season{season_number: 2, episodes: [episode(2, 1)]}
      ])

    assert DownloadScope.units(selection, :first_missing_season) == [{1, 2}]
  end

  test "first_missing_season moves past a season with nothing pickable" do
    selection =
      selection([
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1, tracked?: true)]},
        %Targeting.Season{season_number: 2, episodes: [episode(2, 1), episode(2, 2, aired?: false)]}
      ])

    assert DownloadScope.units(selection, :first_missing_season) == [{2, 1}]
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

  test "latest_season is the pickable episodes of the highest season with an aired episode" do
    selection =
      selection([
        %Targeting.Season{season_number: 0, episodes: [episode(0, 1)]},
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1)]},
        %Targeting.Season{
          season_number: 2,
          episodes: [episode(2, 1, in_library?: true), episode(2, 2), episode(2, 3, aired?: false)]
        },
        %Targeting.Season{season_number: 3, episodes: [episode(3, 1, aired?: false)]}
      ])

    assert DownloadScope.units(selection, :latest_season) == [{2, 2}]
  end

  test "latest_season is nothing when the latest aired season is already had" do
    selection =
      selection([
        %Targeting.Season{season_number: 1, episodes: [episode(1, 1)]},
        %Targeting.Season{
          season_number: 2,
          episodes: [episode(2, 1, in_library?: true), episode(2, 2, tracked?: true)]
        }
      ])

    assert DownloadScope.units(selection, :latest_season) == []
  end

  test "latest_season never falls to the specials" do
    selection = selection([%Targeting.Season{season_number: 0, episodes: [episode(0, 1)]}])

    assert DownloadScope.units(selection, :latest_season) == []
  end

  test "an empty universe yields no units for any scope" do
    for scope <- DownloadScope.scopes() do
      assert DownloadScope.units(selection([]), scope) == []
    end
  end

  test "scopes are the closed set in menu order, parsed from their wire form" do
    assert DownloadScope.scopes() == [:first_missing_season, :everything, :latest_season]
    assert DownloadScope.parse("latest_season") == {:ok, :latest_season}
    assert DownloadScope.parse("first_season") == :error
    assert DownloadScope.parse(nil) == :error
  end
end
