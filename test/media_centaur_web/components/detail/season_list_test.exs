defmodule MediaCentaurWeb.Components.Detail.SeasonListTest do
  use MediaCentaurWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MediaCentaurWeb.Components.Detail.SeasonList
  alias MediaCentaurWeb.ViewModel.EpisodeRow
  alias MediaCentaurWeb.ViewModel.SeasonView

  defp season_view do
    %SeasonView{
      season_number: 1,
      name: "Season 1",
      kind: :library,
      items: [
        %EpisodeRow.Missing{
          season_number: 1,
          episode_number: 2,
          title: "Second Sample",
          air_date: Date.add(Date.utc_today(), -3)
        }
      ],
      extras: [],
      watched_count: 0,
      total_count: 2
    }
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        seasons: [season_view()],
        entity_id: "entity-1",
        expanded_seasons: MapSet.new([1]),
        expanded_item_details: MapSet.new(),
        all_episode_details_open: false,
        extras: [],
        extra_progress_by_id: %{},
        on_play: "play",
        spoiler_free: false,
        available: true,
        series_tmdb_id: "4556",
        acquisition?: true
      },
      overrides
    )
  end

  describe "Download more of this show" do
    test "links to the plan picker for the series" do
      html = render_component(&SeasonList.season_list/1, assigns(%{}))

      assert html =~ "Download more of this show"
      assert html =~ "/incoming?plan=new&amp;tmdb_id=4556&amp;tmdb_type=tv"
    end

    test "absent without a TMDB id" do
      html = render_component(&SeasonList.season_list/1, assigns(%{series_tmdb_id: nil}))

      refute html =~ "Download more of this show"
    end

    test "absent when acquisition is not configured" do
      html = render_component(&SeasonList.season_list/1, assigns(%{acquisition?: false}))

      refute html =~ "Download more of this show"
    end
  end

  describe "the missing episode row" do
    test "carries the download event and the episode's title and date" do
      html = render_component(&SeasonList.season_list/1, assigns(%{}))

      assert html =~ ~s(phx-click="download_missing_episode")
      assert html =~ ~s(phx-value-season="1")
      assert html =~ ~s(phx-value-episode="2")
      assert html =~ "Second Sample"
      assert html =~ "aired 3d ago"
    end

    test "is inert and unfocusable without acquisition" do
      html = render_component(&SeasonList.season_list/1, assigns(%{acquisition?: false}))

      assert html =~ ~s(data-role="missing-episode-row")
      refute html =~ "download_missing_episode"
      refute html =~ ~s(data-nav-item tabindex="0"><div class="flex items-center gap-3 text-sm">)
    end

    test "falls back to the episode number when the list has no title" do
      season = %{season_view() | items: [%EpisodeRow.Missing{season_number: 1, episode_number: 4}]}
      html = render_component(&SeasonList.season_list/1, assigns(%{seasons: [season]}))

      assert html =~ "Episode 4"
    end
  end

  describe "the in-flight episode row" do
    test "says it is downloading and offers nothing to click" do
      season = %{
        season_view()
        | items: [
            %EpisodeRow.InFlight{
              season_number: 1,
              episode_number: 2,
              title: "Second Sample",
              air_date: Date.add(Date.utc_today(), -3)
            }
          ]
      }

      html = render_component(&SeasonList.season_list/1, assigns(%{seasons: [season]}))

      assert html =~ ~s(data-role="in-flight-episode-row")
      assert html =~ "Downloading"
      assert html =~ "Second Sample"
      refute html =~ "download_missing_episode"
      refute html =~ ~s(data-role="missing-episode-row")
    end
  end
end
