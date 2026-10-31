defmodule MediaCentaurWeb.DiscoveryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Features

  describe "the feature (ADR-081)" do
    test "off by default: no sidebar entry, and the page is its off state", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery")

      refute has_element?(view, "[data-tip='Discovery']")
      assert has_element?(view, "#discovery-off")
      assert render(view) =~ "Discovery is off"
    end

    test "Turn on sets the flag and mounts the page, whose entry is in the sidebar", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery")

      view |> element("#discovery-off-turn-on") |> render_click()
      assert Features.enabled?(:discovery)
      assert_redirect(view, "/discovery")

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "[data-tip='Discovery']")
      assert has_element?(view, "#discovery-empty")
      assert render(view) =~ "Recent digital releases will land here"
    end

    test "the Feature flags row says it is in development", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/settings?section=features")
      assert html =~ "In development."
    end
  end
end
