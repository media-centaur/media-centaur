defmodule MediaCentaurWeb.LibraryLiveTrackingTest do
  @moduledoc """
  A title the library holds opens to be watched (UIDR-042, amended
  2026-11-08): its modal carries the bookmark in the action row and no
  tracking card under the content, whatever rung the title sits at. The
  switches, the caught-up point and the dates for an owned series are
  the Watchlist page's. The one per-title acquisition setting an owned
  title keeps, the lower-quality acceptance, sits behind the cog.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Watchlist
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

  test "a series at Auto-grab opens with Play and the filled bookmark, and no tracking card",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/library?title=tv_series-424242")

    assert has_element?(view, "#detail-modal button[phx-click='play']")
    # Listed at any rung: the bookmark is filled and a click removes the
    # title — one act (spec 2026-09-14).
    assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true'][phx-value-choice='off']")
    refute has_element?(view, "#detail-tracking")
    refute has_element?(view, "#detail-tracking-controls")
    refute has_element?(view, "#detail-caught-up")
    refute has_element?(view, "#detail-release-dates")
  end

  test "the bookmark deletes the tracked title and its calendar; listing it again shows no card", %{
    conn: conn,
    item: item
  } do
    {:ok, view, _html} = live(conn, "/library?title=tv_series-424242")

    view |> element("#detail-watchlist-toggle") |> render_click()
    await_supervised_tasks()

    assert Watchlist.rung(424_242, :tv_series) == nil
    refute ReleaseTracking.get_item(item.id), "Off deletes the tracked title"
    assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='false']")

    view |> element("#detail-watchlist-toggle") |> render_click()
    # Listing fetches artwork on a supervised task; drive it home (ADR-049).
    await_supervised_tasks()

    assert Watchlist.rung(424_242, :tv_series) == :list
    assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true']")
    refute has_element?(view, "#detail-tracking")
  end

  # Moved behind the cog on 2026-09-13: it is a setting you reset once,
  # not a row to read past on the way to the episode list.
  test "the per-title quality acceptance is shown and reset from Manage", %{conn: conn, item: item} do
    {:ok, _} =
      MediaCentaur.Acquisition.TitleDownloadParams.put(item.tmdb_id, item.media_type, %{
        min_quality: "any"
      })

    {:ok, view, _html} = live(conn, "/library?title=tv_series-424242")

    # The episode list is not where it goes: an owned title carries the
    # acceptance behind the cog and nowhere else.
    refute has_element?(view, "#detail-lower-quality")
    refute has_element?(view, "[data-role='lower-quality-note']")

    {:ok, view, _html} = live(conn, "/library?title=tv_series-424242&view=info")

    assert has_element?(view, "#manage-lower-quality")

    view
    |> element("#manage-lower-quality button[phx-click='reset_lower_quality']")
    |> render_click()

    assert MediaCentaur.Acquisition.TitleDownloadParams.get(item.tmdb_id, item.media_type).min_quality ==
             nil

    refute has_element?(view, "#manage-lower-quality")
  end
end
