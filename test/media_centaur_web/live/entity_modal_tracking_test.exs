defmodule MediaCentaurWeb.EntityModalTrackingTest do
  @moduledoc """
  The library detail's tracking block (UIDR-035): the ladder control
  always, and the release timeline while the series is followed. Moving
  the rung is the one act; dropping below Follow deletes the tracked
  title, which is why the timeline goes with it.
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

    create_title_intent(%{
      tmdb_id: 424_242,
      media_type: :tv_series,
      name: "Tracked Fixture Show",
      rung: :default
    })

    {:ok, series: series, item: item}
  end

  test "a tracked series carries the timeline and the control under its seasons; no bell",
       %{conn: conn, series: series} do
    {:ok, view, html} = live(conn, "/library?selected=#{series.id}")

    assert has_element?(view, "#detail-tracking[data-nav-zone='detail_tracking']")
    assert has_element?(view, "#detail-release-timeline-next", "S02E01")
    assert has_element?(view, "#detail-tracking-mode[data-rung='default']")
    refute has_element?(view, "[phx-click='toggle_tracking']")
    refute html =~ "hero-bell"
  end

  test "the control moves the rung; Off deletes the tracked title and its timeline", %{
    conn: conn,
    series: series,
    item: item
  } do
    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}")

    view |> element("#detail-tracking-mode-grab") |> render_click()
    await_supervised_tasks()
    assert Discovery.rung(424_242, :tv_series) == :grab
    assert has_element?(view, "#detail-tracking-mode[data-rung='grab']")

    view |> element("#detail-tracking-mode-off") |> render_click()
    await_supervised_tasks()

    assert Discovery.rung(424_242, :tv_series) == nil
    refute ReleaseTracking.get_item(item.id), "Off deletes the tracked title"
    assert has_element?(view, "#detail-tracking-mode[data-rung='off']")
    refute has_element?(view, "#detail-release-timeline")
  end

  test "raising an unfollowed series from Off follows it and lists it", %{
    conn: conn,
    series: series
  } do
    {:ok, nil} =
      ReleaseTracking.set_rung(
        MediaCentaur.TMDB.Title.new!(%{
          tmdb_id: 424_242,
          media_type: :tv_series,
          name: "Tracked Fixture Show"
        }),
        :off
      )

    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}")
    assert has_element?(view, "#detail-tracking-mode[data-rung='off']")

    view |> element("#detail-tracking-mode-ask") |> render_click()
    await_supervised_tasks()

    assert Discovery.rung(424_242, :tv_series) == :ask
    assert Discovery.listed?(424_242, :tv_series)
    assert has_element?(view, "#detail-tracking-mode[data-rung='ask']")
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
