defmodule MediaCentaurWeb.Live.SidebarTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  # /guide is the lightest page under live_session :default.
  @page "/guide"

  test "the rail is two named groups, and the current page is the one active entry", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @page)
    assert has_element?(view, "#sidebar nav[aria-label='Watch'] > #sidebar-home")
    assert has_element?(view, "#sidebar nav#sidebar-system[aria-label='System'] > #sidebar-settings")
    refute has_element?(view, "#sidebar [aria-current]")

    {:ok, view, _html} = live_async!(conn, "/settings")
    assert has_element?(view, "#sidebar-settings.sidebar-link-active[aria-current='page']")
    refute has_element?(view, "#sidebar-home[aria-current]")
  end
end
