defmodule MediaCentaurWeb.SettingsLive.ControlsTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Settings.Controls

  describe "mount" do
    test "renders all bindings grouped by category", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=controls")
      rendered = render(view)

      assert rendered =~ "Controls"
      assert rendered =~ "Navigation"
      assert rendered =~ "Zones"
      assert rendered =~ "Playback"
      assert rendered =~ "System"
      assert rendered =~ "Move up"
      assert rendered =~ "Toggle console"
    end
  end

  describe "remap flow" do
    test "clicking remap enters listening state", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=controls")

      view
      |> element(
        ~s|button[phx-click="controls:listen"][phx-value-id="navigate_up"][phx-value-kind="keyboard"]|
      )
      |> render_click()

      assert has_element?(view, "[data-listening='true']")
    end

    test "controls:bind event persists and broadcasts", %{conn: conn} do
      :ok = Controls.subscribe()
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=controls")

      render_hook(view, "controls:bind", %{"id" => "play", "kind" => "keyboard", "value" => "k"})
      assert_receive {:controls_changed, map}
      assert map[:play].key == "k"
    end

    test "controls:cancel leaves state unchanged", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=controls")

      view
      |> element(
        ~s|button[phx-click="controls:listen"][phx-value-id="navigate_up"][phx-value-kind="keyboard"]|
      )
      |> render_click()

      render_hook(view, "controls:cancel", %{})
      refute has_element?(view, "[data-listening='true']")
    end
  end

  describe "clear and reset" do
    test "clicking clear unsets the binding", %{conn: conn} do
      :ok = Controls.subscribe()
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=controls")

      view
      |> element(~s|button[phx-click="controls:clear"][phx-value-id="back"][phx-value-kind="keyboard"]|)
      |> render_click()

      assert_receive {:controls_changed, map}
      assert map[:back].key == nil
    end

    test "reset_all button restores defaults", %{conn: conn} do
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      :ok = Controls.subscribe()
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=controls")

      # The first click only arms (MC0027 tier 2); nothing is reset yet.
      html = render_click(view, "controls:reset_all", %{})
      assert html =~ "Click again to reset every binding"
      refute_receive {:controls_changed, _}, 100

      render_click(view, "controls:reset_all", %{})

      assert_receive {:controls_changed, map}
      assert map[:navigate_up].key == "ArrowUp"
    end

    test "reset_category button restores that category only", %{conn: conn} do
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      {:ok, _} = Controls.put(:play, :keyboard, "k")
      :ok = Controls.subscribe()
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=controls")

      view
      |> element(~s|button[phx-click="controls:reset_category"][phx-value-category="navigation"]|)
      |> render_click()

      assert_receive {:controls_changed, map}
      assert map[:navigate_up].key == "ArrowUp"
      assert map[:play].key == "k"
    end
  end

  describe "glyph style toggle" do
    test "switches between xbox and playstation", %{conn: conn} do
      :ok = Controls.subscribe()
      {:ok, view, _html} = live_async!(conn, ~p"/settings?section=controls")

      view
      |> element(~s|button[phx-click="controls:set_glyph"][phx-value-style="playstation"]|)
      |> render_click()

      assert_receive {:controls_changed, _}
      assert Controls.glyph_style() == "playstation"
    end
  end
end
