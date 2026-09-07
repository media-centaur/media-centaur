defmodule MediaCentaurWeb.EntityModalTrackingTest do
  @moduledoc """
  The library detail's tracking block (UIDR-035): a tracked series shows
  the release timeline and the tracking-mode control under its seasons;
  the control moves the mode, Off disarms and hides the timeline, and a
  raise from Off arms — which lists the series on the watchlist.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Discovery
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    TmdbStubs.setup_artwork_cache()

    series = create_tv_series(%{name: "Tracked Fixture Show", tmdb_id: "424242"})
    season = create_season(%{tv_series_id: series.id, season_number: 1})

    create_episode(%{
      season_id: season.id,
      episode_number: 1,
      name: "Episode S1E1",
      content_url: "/tv/tracked-fixture/s01e01.mkv"
    })

    item =
      create_tracking_item(%{
        tmdb_id: 424_242,
        media_type: :tv_series,
        name: "Tracked Fixture Show",
        library_container_type: :tv_series,
        library_container_id: series.id
      })

    create_tracking_release(%{
      item_id: item.id,
      air_date: Date.add(Date.utc_today(), 6),
      season_number: 2,
      episode_number: 1,
      released: false
    })

    {:ok, series: series, item: item}
  end

  test "a tracked series carries the timeline and the control under its seasons; no bell",
       %{conn: conn, series: series} do
    {:ok, view, html} = live(conn, "/library?selected=#{series.id}")

    assert has_element?(view, "#detail-tracking[data-nav-zone='detail_tracking']")
    assert has_element?(view, "#detail-release-timeline-next", "S02E01")
    assert has_element?(view, "#detail-tracking-mode[data-mode='global']")
    refute has_element?(view, "[phx-click='toggle_tracking']")
    refute html =~ "hero-bell"
  end

  test "the control moves the mode; Off disarms and hides the timeline", %{
    conn: conn,
    series: series,
    item: item
  } do
    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}")

    view |> element("#detail-tracking-mode-grab") |> render_click()
    assert ReleaseTracking.get_item(item.id).tracking_mode == :grab
    assert has_element?(view, "#detail-tracking-mode[data-mode='grab']")

    view |> element("#detail-tracking-mode-none") |> render_click()
    assert ReleaseTracking.get_item(item.id).tracking_mode == :none
    assert has_element?(view, "#detail-tracking-mode[data-mode='none']")
    refute has_element?(view, "#detail-release-timeline")
  end

  test "raising a disarmed series arms it — on the watchlist, at the chosen mode", %{
    conn: conn,
    series: series,
    item: item
  } do
    {:ok, _} = ReleaseTracking.disarm(item)
    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}")

    # Off and unlisted: the copy states the consequence before the click.
    assert has_element?(view, "#detail-tracking-mode-watchlist-note")

    view |> element("#detail-tracking-mode-ask") |> render_click()
    await_supervised_tasks()

    assert ReleaseTracking.get_item(item.id).tracking_mode == :ask
    assert Discovery.on_watchlist?(424_242, :tv_series)
    assert has_element?(view, "#detail-tracking-mode[data-mode='ask']")
    assert has_element?(view, "#detail-release-timeline")
  end

  test "the per-title quality acceptance is shown and reset from the block", %{
    conn: conn,
    series: series,
    item: item
  } do
    {:ok, _} =
      MediaCentaur.Acquisition.TitleDownloadParams.put(item.tmdb_id, item.media_type, %{
        min_quality: "any"
      })

    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}")

    assert has_element?(view, "#detail-tracking-mode-lower-quality")

    view
    |> element("#detail-tracking-mode-lower-quality button[phx-click='reset_lower_quality']")
    |> render_click()

    assert MediaCentaur.Acquisition.TitleDownloadParams.get(item.tmdb_id, item.media_type).min_quality ==
             nil

    refute has_element?(view, "#detail-tracking-mode-lower-quality")
  end

  test "an untracked series shows no tracking block", %{conn: conn} do
    plain = create_tv_series(%{name: "Plain Fixture Show"})
    season = create_season(%{tv_series_id: plain.id, season_number: 1})

    create_episode(%{
      season_id: season.id,
      episode_number: 1,
      name: "Episode S1E1",
      content_url: "/tv/plain-fixture/s01e01.mkv"
    })

    {:ok, view, _html} = live(conn, "/library?selected=#{plain.id}")
    refute has_element?(view, "#detail-tracking")
  end
end
