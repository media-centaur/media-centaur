defmodule MediaCentaurWeb.Storybook.Watchlist.CaughtUpPanel do
  @moduledoc """
  The caught-up panel (campaign `discovery.md`, M16, amended 2026-11-08):
  where you stand in a followed series, movable to any aired episode.
  Anchored under a Watchlist row's state line; here shown in place with
  a stand-in trigger above it. The states: a short series open on its
  point, the same with a chip selected (Set point armed), a long daily
  serial whose grid scrolls, Nothing yet selected, the season list open,
  a season still loading, a season TMDB did not answer for.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.WatchlistLive.CaughtUpLogic.Panel

  def function, do: &MediaCentaurWeb.Components.Watchlist.CaughtUpPanel.caught_up_panel/1
  def render_source, do: :function
  def layout, do: :one_column

  @today ~D[2026-11-08]

  def template do
    """
    <div class="flex justify-end pb-[30rem]">
      <div class="glass-menu inline-flex">
        <span class="glass-menu-trigger" aria-hidden="true">Caught up through S02E05</span>
        <.psb-variation/>
      </div>
    </div>
    """
  end

  defp seasons(count, per_season, first_year) do
    for number <- count..1//-1 do
      %{number: number, year: first_year + number - 1, count: per_season}
    end
  end

  # Episodes `gap_days` apart, the `aired` first ones on or before today.
  defp episodes(count, aired, gap_days) do
    for number <- 1..count do
      %{
        number: number,
        name: "Episode #{number}",
        air_date: Date.add(@today, round((number - aired) * gap_days) - 1)
      }
    end
  end

  defp panel(overrides) do
    struct!(
      Panel,
      Map.merge(
        %{
          ref: {42, :tv_series},
          id: "story-caught-up-panel",
          point: {2, 5},
          latest: {2, 5},
          seasons: seasons(2, 8, 2024),
          season: 2,
          episodes: episodes(8, 5, 7),
          selection: {2, 5}
        },
        Map.new(overrides)
      )
    )
  end

  def variations do
    [
      %Variation{
        id: :short_series,
        description:
          "A two-season series open on its point, S02E05: the five aired chips had, three ahead unaired. Set point is disabled until the selection moves.",
        attributes: %{today: @today, panel: panel([])}
      },
      %Variation{
        id: :selection_moved,
        description:
          "S02E03 selected: the chips after it that have aired turn amber — what Auto-grab will want — and Set point is armed.",
        attributes: %{today: @today, panel: panel(selection: {2, 3})}
      },
      %Variation{
        id: :library_had,
        description:
          "The library holds S02E04 and S02E05 and the watermark says S01E08: those chips stay blue whatever the selection.",
        attributes: %{
          today: @today,
          panel: panel(selection: {2, 2}, had: MapSet.new([{2, 4}, {2, 5}]), watermark: {1, 8})
        }
      },
      %Variation{
        id: :long_serial,
        description:
          "A daytime serial in its thirty-eighth year, 250 episodes a season: the select carries every season and the grid scrolls inside its height.",
        attributes: %{
          today: @today,
          panel:
            panel(
              point: {38, 112},
              latest: {38, 115},
              seasons: seasons(38, 250, 1988),
              season: 38,
              episodes: episodes(250, 115, 1.4),
              selection: {38, 112}
            )
        }
      },
      %Variation{
        id: :nothing_yet,
        description: "Nothing yet: no point, every aired chip out; Set point will clear the point.",
        attributes: %{today: @today, panel: panel(selection: :none)}
      },
      %Variation{
        id: :no_point,
        description: "A series followed with no point and nothing selected: nothing to set.",
        attributes: %{today: @today, panel: panel(point: nil, selection: :none)}
      },
      %Variation{
        id: :season_list_open,
        description: "The season list open, newest first, the chosen one marked.",
        attributes: %{today: @today, panel: panel(menu_open?: true)}
      },
      %Variation{
        id: :loading,
        description: "A season the store lacks, being read from TMDB.",
        attributes: %{today: @today, panel: panel(season: 1, episodes: :loading)}
      },
      %Variation{
        id: :unavailable,
        description: "TMDB did not answer for the chosen season.",
        attributes: %{today: @today, panel: panel(season: 1, episodes: :unavailable)}
      }
    ]
  end
end
