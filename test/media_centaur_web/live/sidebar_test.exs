defmodule MediaCentaurWeb.Live.SidebarTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  # /guide is the lightest page under live_session :default.
  @page "/guide"

  test "the rail is two named groups, and the current page is the one active entry", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @page)
    assert has_element?(view, "#sidebar nav[aria-label='Watch'] > #sidebar-home")
    # The Watchlist entry is unconditional: the list exists whatever is on (UIDR-057, amended).
    assert has_element?(
             view,
             "#sidebar nav[aria-label='Watch'] > [aria-label='Discovery'] + [aria-label='Watchlist'] + [aria-label='Downloads']"
           )

    assert has_element?(view, "#sidebar nav#sidebar-system[aria-label='System'] > #sidebar-settings")
    refute has_element?(view, "#sidebar [aria-current]")

    {:ok, view, _html} = live_async!(conn, "/settings")
    assert has_element?(view, "#sidebar-settings.sidebar-link-active[aria-current='page']")
    refute has_element?(view, "#sidebar-home[aria-current]")
  end

  test "with files waiting, Review stands in the Watch group just above Downloads", %{conn: conn} do
    MediaCentaur.TestFactory.create_pending_file()

    {:ok, view, _html} = live_async!(conn, @page)

    assert has_element?(
             view,
             "#sidebar nav[aria-label='Watch'] > [aria-label='Watchlist'] + #sidebar-review + [aria-label='Downloads']"
           )

    refute has_element?(view, "#sidebar-system #sidebar-review")
  end

  # The phone carries watch + choose (`campaigns/adaptive-layout.md`): the
  # compact shell's bar is these entries and no other; Watchlist is reached
  # through See all, and the rest stay on the desktop.
  test "the compact shell is Home, Library, Discovery, Social and the profile switcher", %{conn: conn} do
    MediaCentaur.TestFactory.create_pending_file()
    {:ok, view, _html} = live_async!(conn, @page)

    for id <- ~w(sidebar-home sidebar-library sidebar-discovery sidebar-social) do
      assert has_element?(view, "##{id}[data-compact]"), "#{id} belongs in the compact shell"
    end

    for id <-
          ~w(sidebar-watchlist sidebar-review sidebar-downloads sidebar-apps sidebar-status sidebar-settings) do
      refute has_element?(view, "##{id}[data-compact]"), "#{id} is desktop-only"
    end
  end
end
