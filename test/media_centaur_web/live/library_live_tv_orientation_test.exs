defmodule MediaCentaurWeb.LibraryLiveTvOrientationTest do
  @moduledoc """
  TV detail orientation (2026-08-04 design): the hero carries orientation
  (marquee + hairline + subline), seasons open collapsed with dense
  episode rows, and per-episode synopsis lives behind a disclosure.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  defp create_series_with_two_seasons(_context) do
    tv_series = create_tv_series(%{name: "Orientation Fixture Show"})

    season_one = create_season(%{tv_series_id: tv_series.id, season_number: 1})
    season_two = create_season(%{tv_series_id: tv_series.id, season_number: 2})

    episodes =
      for {season, episode_number} <- [
            {season_one, 1},
            {season_two, 1},
            {season_two, 2},
            {season_two, 3}
          ] do
        create_episode(%{
          season_id: season.id,
          episode_number: episode_number,
          name: "Episode S#{season.season_number}E#{episode_number}",
          description: "Synopsis for S#{season.season_number}E#{episode_number}",
          duration_seconds: 1260,
          content_url: "/tv/orientation-show/s0#{season.season_number}e0#{episode_number}.mkv"
        })
      end

    # Season 1 (one episode) fully watched; season 2 untouched → next up
    # is S2E1. Exactly ONE watched record on purpose: the resume walk
    # advances from the most-recently-watched episode, and the changeset
    # stamps `last_watched_at` itself at second granularity — two
    # same-second watched records would tie and make "most recent" (and
    # therefore this whole test) ambiguous.
    [first_episode | _rest] = episodes

    create_watch_progress(%{
      episode_id: first_episode.id,
      position_seconds: 0.0,
      duration_seconds: 0.0,
      completed: true
    })

    {:ok, tv_series: tv_series}
  end

  describe "TV detail orientation" do
    setup :create_series_with_two_seasons

    test "seasons open collapsed — no episode rows, no resume target on load",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      refute has_element?(view, ~s|[data-role="episode-row"]|)
      refute has_element?(view, "[data-resume-target]")
      assert has_element?(view, ~s|button[phx-click="toggle_season"][phx-value-season="1"]|)
      assert has_element?(view, ~s|button[phx-click="toggle_season"][phx-value-season="2"]|)
    end

    test "hero renders marquee, hairline, and subline for the next episode",
         %{conn: conn, tv_series: tv_series} do
      {:ok, _view, html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # Marquee position (S2 · E1), season hairline, and the whisper
      # subline derived from the same season counts the accordion shows.
      assert html =~ "Up next"
      assert html =~ "S2"
      assert html =~ "E1"
      assert html =~ "season-hairline"
      assert html =~ "0 of 3 this season"
      assert html =~ "25% of the series"
    end

    test "expanding a season renders dense rows without synopses",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      view
      |> element(~s|button[phx-click="toggle_season"][phx-value-season="2"]|)
      |> render_click()

      assert has_element?(view, ~s|[data-role="episode-row"]|)
      refute render(view) =~ "Synopsis for S2E1"
    end

    test "the episode-details disclosure reveals the synopsis inline",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      view
      |> element(~s|button[phx-click="toggle_season"][phx-value-season="2"]|)
      |> render_click()

      view
      |> element(
        ~s|button[phx-click="toggle_episode_details"][phx-value-season="2"][phx-value-episode="1"]|
      )
      |> render_click()

      assert render(view) =~ "Synopsis for S2E1"

      view
      |> element(
        ~s|button[phx-click="toggle_episode_details"][phx-value-season="2"][phx-value-episode="1"]|
      )
      |> render_click()

      refute render(view) =~ "Synopsis for S2E1"
    end

    test "fully watched series states completion instead of a next episode",
         %{conn: conn, tv_series: tv_series} do
      for season <- MediaCentaur.Library.list_seasons_for_tv_series(tv_series.id),
          episode <- MediaCentaur.Library.list_episodes_for_season(season.id) do
        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 0.0,
          duration_seconds: 0.0,
          completed: true
        })
      end

      {:ok, _view, html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      assert html =~ "Series complete"
      assert html =~ "4 episodes watched"
    end
  end
end
