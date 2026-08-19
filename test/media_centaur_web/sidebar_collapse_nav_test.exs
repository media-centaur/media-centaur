defmodule MediaCentaurWeb.SidebarCollapseNavTest do
  @moduledoc """
  Pins the sidebar collapse toggle's input-system contract: the button is a
  nav item (keyboard/gamepad can walk to it) and carries
  `data-nav-defer-activate` so activate-on-focus — which clicks sidebar
  entries as the cursor passes over them — never toggles the rail in
  passing. Only an explicit SELECT flips it.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "collapse toggle is a deferred-activation nav item", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(#sidebar button[data-nav-item][data-nav-defer-activate][tabindex="0"])
           )
  end
end
