defmodule MediaCentaurWeb.LibraryLiveTvOrientationTest do
  @moduledoc """
  TV detail orientation (2026-08-04 design, auto-orient revision
  2026-08-05): the hero carries the hairline, the season holding the
  next episode opens expanded and the document opens scrolled to that
  episode, and per-episode synopsis lives behind a disclosure.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  defp create_series_with_two_seasons(_context) do
    tv_series =
      create_tv_series(%{
        name: "Orientation Fixture Show",
        description: "A sample synopsis about a fictional workplace.",
        genres: ["Comedy"],
        network: "Sample Network",
        aggregate_rating_value: 7.5,
        vote_count: 802
      })

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

    test "the season holding the next episode opens expanded and scrolled to it",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # Next up is S2E1, so season 2 opens expanded with a scroll target
      # and season 1 (fully watched) stays collapsed.
      assert has_element?(view, ~s|[data-role="episode-row"][data-resume-target]|)
      assert html =~ "Episode S2E1"
      refute html =~ "Episode S1E1"
      assert has_element?(view, ~s|#detail-content[data-scroll-to-resume]|)
      assert has_element?(view, ~s|button[phx-click="toggle_season"][phx-value-season="1"]|)
    end

    test "the expanded season collapses on click like any other",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      view
      |> element(~s|button[phx-click="toggle_season"][phx-value-season="2"]|)
      |> render_click()

      refute has_element?(view, ~s|[data-role="episode-row"]|)
    end

    test "hero carries the hairline; the Play button alone names the next episode",
         %{conn: conn, tv_series: tv_series} do
      {:ok, _view, html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # The up-next marquee was removed as redundant with the Play
      # button's own label — the hairline is the only orientation
      # element, and the description takes the right column.
      assert html =~ "season-hairline"
      assert html =~ "Play S2E1"
      refute html =~ "Up next"
      refute html =~ "orientation-marquee"
      assert html =~ "A sample synopsis about a fictional workplace."
    end

    test "expanding a collapsed season renders dense rows without synopses",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      refute html =~ "Episode S1E1"

      view
      |> element(~s|button[phx-click="toggle_season"][phx-value-season="1"]|)
      |> render_click()

      html = render(view)
      assert html =~ "Episode S1E1"
      refute html =~ "Synopsis for S1E1"
    end

    test "the episode-details disclosure reveals the synopsis inline",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

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

    test "the episode-details toggle opens every synopsis in expanded seasons at once",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      refute render(view) =~ "Synopsis for S2E1"

      view
      |> element(~s|button[phx-click="toggle_all_episode_details"]|)
      |> render_click()

      html = render(view)
      assert html =~ "Synopsis for S2E1"
      assert html =~ "Synopsis for S2E2"
      assert html =~ "Synopsis for S2E3"

      view
      |> element(~s|button[phx-click="toggle_all_episode_details"]|)
      |> render_click()

      refute render(view) =~ "Synopsis for S2E1"
    end

    test "turning the episode-details toggle off keeps per-row disclosures open",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      view
      |> element(
        ~s|button[phx-click="toggle_episode_details"][phx-value-season="2"][phx-value-episode="1"]|
      )
      |> render_click()

      view |> element(~s|button[phx-click="toggle_all_episode_details"]|) |> render_click()
      view |> element(~s|button[phx-click="toggle_all_episode_details"]|) |> render_click()

      html = render(view)
      assert html =~ "Synopsis for S2E1"
      refute html =~ "Synopsis for S2E2"
    end

    test "a fully watched season header shows only the check, no label",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      season_one_header =
        view
        |> element(~s|button[phx-click="toggle_season"][phx-value-season="1"]|)
        |> render()

      refute season_one_header =~ "watched"
      assert season_one_header =~ "hero-check-mini"

      season_two_header =
        view
        |> element(~s|button[phx-click="toggle_season"][phx-value-season="2"]|)
        |> render()

      assert season_two_header =~ "3 remaining"
      refute season_two_header =~ "hero-check-mini"
    end

    test "catalog facts live in More info, not on the main view",
         %{conn: conn, tv_series: tv_series} do
      {:ok, _view, main_html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # The main view carries orientation + actions only — no facet
      # strip (network / rating / genres moved to More info).
      refute main_html =~ "Genres"
      refute main_html =~ "Sample Network"

      {:ok, _view, credits_html} =
        live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=credits")

      assert credits_html =~ "Sample Network"
      assert credits_html =~ "Genres"
      assert credits_html =~ "Comedy"
      assert credits_html =~ "Rating"
      assert credits_html =~ "7.5"
    end

    test "fully watched series states completion instead of a next episode",
         %{conn: conn, tv_series: tv_series} do
      for season <- MediaCentaur.Library.Seasons.list_for_tv_series(tv_series.id),
          episode <- MediaCentaur.Library.Episodes.list_for_season(season.id) do
        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 0.0,
          duration_seconds: 0.0,
          completed: true
        })
      end

      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # No completion marquee — the playback CTA carries the state.
      refute html =~ "Series complete"
      assert html =~ "Watch again"

      # Nothing to return to: every season collapses into a rewatch
      # index and the document opens at the top.
      refute has_element?(view, ~s|[data-role="episode-row"]|)
      refute has_element?(view, ~s|#detail-content[data-scroll-to-resume]|)
    end
  end

  describe "TV detail orientation — unstarted series" do
    setup do
      tv_series = create_tv_series(%{name: "Unstarted Fixture Show"})
      season_one = create_season(%{tv_series_id: tv_series.id, season_number: 1})
      season_two = create_season(%{tv_series_id: tv_series.id, season_number: 2})

      for {season, episode_number} <- [{season_one, 1}, {season_one, 2}, {season_two, 1}] do
        create_episode(%{
          season_id: season.id,
          episode_number: episode_number,
          name: "Episode S#{season.season_number}E#{episode_number}",
          duration_seconds: 1260,
          content_url: "/tv/unstarted-show/s0#{season.season_number}e0#{episode_number}.mkv"
        })
      end

      {:ok, tv_series: tv_series}
    end

    test "season one opens expanded but the document stays on the hero",
         %{conn: conn, tv_series: tv_series} do
      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # A first episode, not a next one — nothing to scroll back to, so
      # the cinematic hero survives the open.
      assert html =~ "Episode S1E1"
      refute html =~ "Episode S2E1"
      refute has_element?(view, ~s|#detail-content[data-scroll-to-resume]|)
    end
  end
end
