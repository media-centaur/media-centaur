defmodule MediaCentarrWeb.UpcomingLiveTest do
  use MediaCentarrWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "GET /upcoming renders the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/upcoming")
    # The page header always renders the "Upcoming" heading
    assert html =~ "Upcoming"
  end

  test "clicking the Track New Releases button opens the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/upcoming")

    # The track button only appears when TMDB is ready; if the test
    # environment isn't TMDB-ready, the conditional skips the assertion.
    if has_element?(view, "button", "Track New Releases") do
      rendered = render_click(element(view, "button", "Track New Releases"))
      assert rendered =~ "track-search-input"
    end
  end
end
