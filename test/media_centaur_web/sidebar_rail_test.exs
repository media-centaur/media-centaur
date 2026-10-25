defmodule MediaCentaurWeb.SidebarRailTest do
  @moduledoc """
  Pins the sidebar's shape: a fixed icon rail. It carries no expand or
  collapse control, draws no label text, and every entry is an icon-only
  link whose name lives in `aria-label` (the Tooltip hook shows the same
  words beside the icon on hover or focus).
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "the rail has no toggle and no labels", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "#sidebar button")
    refute has_element?(view, "#sidebar .sidebar-label")
    refute has_element?(view, "#sidebar .sidebar-group-label")
  end

  test "every entry is an icon-only link with an accessible name", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#sidebar a[data-nav-item][aria-label='Home'][data-tip='Home']")
    refute has_element?(view, "#sidebar [data-nav-item]:not([aria-label])")
    refute has_element?(view, "#sidebar [data-tip]:not([aria-label])")
  end
end
