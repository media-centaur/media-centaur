defmodule MediaCentaurWeb.EntityModalTrackingTest do
  @moduledoc """
  The library detail's tracking block (UIDR-035): the tracking rows
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
      rung: :grab
    })

    {:ok, series: series, item: item}
  end

  test "a tracked series carries the timeline and the rows under its seasons; no bell",
       %{conn: conn, series: series} do
    {:ok, view, html} = live(conn, "/library?selected=#{series.id}")

    assert has_element?(view, "#detail-tracking[data-nav-zone='detail_tracking']")
    assert has_element?(view, "#detail-release-dates", "S02E01")
    assert has_element?(view, "#detail-tracking-controls[data-rung='grab']")
    assert has_element?(view, "#detail-tracking-controls-track[aria-disabled='true']")
    # Listed at any rung: the bookmark is filled and a click removes the
    # title — one act (spec 2026-09-14).
    assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true'][phx-value-choice='off']")
    refute has_element?(view, "[phx-click='toggle_tracking']")
    refute html =~ "hero-bell"
  end

  test "the rows move the rung; the bookmark deletes the tracked title and its timeline", %{
    conn: conn,
    series: series,
    item: item
  } do
    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}")

    view |> element("#detail-tracking-controls-grab") |> render_click()
    await_supervised_tasks()
    assert Discovery.rung(424_242, :tv_series) == :follow
    assert has_element?(view, "#detail-tracking-controls[data-rung='follow']")
    assert has_element?(view, "#detail-release-dates")

    view |> element("#detail-watchlist-toggle") |> render_click()
    await_supervised_tasks()

    assert Discovery.rung(424_242, :tv_series) == nil
    refute ReleaseTracking.get_item(item.id), "Off deletes the tracked title"
    # Off leaves nothing to show: no switches, no dates, no card.
    refute has_element?(view, "#detail-tracking")
    refute has_element?(view, "#detail-release-dates")
  end

  test "an owned series not on the list offers Add to watchlist; the rows follow, and raise it", %{
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

    # Owning a series is not listing it (UIDR-039): the action row's
    # bookmark is the one verb until the title is on the list, and there
    # is no tracking card at all until then.
    assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='false']")
    refute has_element?(view, "#detail-tracking")

    view |> element("#detail-watchlist-toggle") |> render_click()
    # Listing fetches artwork on a supervised task; drive it home (ADR-049).
    await_supervised_tasks()
    assert Discovery.rung(424_242, :tv_series) == :list
    assert has_element?(view, "#detail-tracking-controls[data-rung='list']")
    assert has_element?(view, "#detail-tracking-controls-track[phx-value-choice='follow']")

    view |> element("#detail-tracking-controls-grab") |> render_click()
    await_supervised_tasks()

    assert Discovery.rung(424_242, :tv_series) == :grab
    assert Discovery.listed?(424_242, :tv_series)
    assert has_element?(view, "#detail-tracking-controls[data-rung='grab']")
  end

  # Moved behind the cog on 2026-09-13: it is a setting you reset once,
  # not a row to read past on the way to the episode list.
  test "the per-title quality acceptance is shown and reset from Manage", %{
    conn: conn,
    series: series,
    item: item
  } do
    {:ok, _} =
      MediaCentaur.Acquisition.TitleDownloadParams.put(item.tmdb_id, item.media_type, %{
        min_quality: "any"
      })

    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}")

    refute has_element?(view, "#detail-tracking #manage-lower-quality")

    {:ok, view, _html} = live(conn, "/library?selected=#{series.id}&view=info")

    assert has_element?(view, "#manage-lower-quality")

    view
    |> element("#manage-lower-quality button[phx-click='reset_lower_quality']")
    |> render_click()

    assert MediaCentaur.Acquisition.TitleDownloadParams.get(item.tmdb_id, item.media_type).min_quality ==
             nil

    refute has_element?(view, "#manage-lower-quality")
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
