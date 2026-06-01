defmodule MediaCentaurWeb.StatusLive.HealthBoardLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders a tile per subsystem and opens a drill-in on ?subsystem=", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    assert has_element?(view, "#subsystem-tile-pipeline")
    assert has_element?(view, "#subsystem-tile-watcher")

    {:ok, view, _html} = live(conn, ~p"/status?subsystem=pipeline")
    assert has_element?(view, "#health-drill-in", "Import")
  end

  test "clicking a tile patches to that subsystem", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/status")
    view |> element("#subsystem-tile-tmdb") |> render_click()
    assert_patch(view, ~p"/status?subsystem=tmdb")
    assert has_element?(view, "#health-drill-in", "Metadata")
  end
end
