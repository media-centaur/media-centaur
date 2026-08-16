defmodule MediaCentaurWeb.SettingsLiveDangerTest do
  @moduledoc """
  The Danger Zone's two confirmation treatments (Stage 8 of the
  audit-remediation campaign, enforced by Credo MC0027).

  Both actions used the native `data-confirm` dialog, which is unthemed and
  cannot be answered with a d-pad. What replaced them is graded by
  consequence: clearing the database is irreversible and unbounded, so it
  earns a persistent modal; refreshing the image cache only costs time, so
  the button arms in place. The grading also decides the section each lives
  in — Clear database stays in Danger Zone, the recoverable image-cache
  refresh sits with the other repair actions in Maintenance.

  These tests deliberately stop short of firing either action. The
  regression they guard is that **one click no longer does the thing** — and
  actually clearing the database or deleting the artwork cache is not
  something a unit test should do to prove it.
  """
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defp open_danger_section(conn) do
    {:ok, view, _html} = live(conn, "/settings?section=danger")
    _ = render_async(view)
    view
  end

  defp open_maintenance_section(conn) do
    {:ok, view, _html} = live(conn, "/settings?section=maintenance")
    _ = render_async(view)
    view
  end

  describe "clear database — persistent modal" do
    test "the confirmation modal is in the DOM and closed on arrival", %{conn: conn} do
      view = open_danger_section(conn)

      assert has_element?(view, "#clear-database-modal[data-state='closed']")
    end

    test "clicking Clear opens the modal instead of clearing", %{conn: conn} do
      view = open_danger_section(conn)

      html =
        view
        |> element("button[phx-click='clear_database_prompt']")
        |> render_click()

      assert has_element?(view, "#clear-database-modal[data-state='open']")
      refute html =~ "Clearing…"
    end

    test "the modal's confirm button is what actually clears", %{conn: conn} do
      view = open_danger_section(conn)

      view
      |> element("button[phx-click='clear_database_prompt']")
      |> render_click()

      assert has_element?(view, "#clear-database-modal button[phx-click='clear_database']")
    end

    test "cancelling closes the modal without clearing", %{conn: conn} do
      view = open_danger_section(conn)

      view
      |> element("button[phx-click='clear_database_prompt']")
      |> render_click()

      html =
        view
        |> element("#clear-database-modal button[phx-click='cancel_clear_database']")
        |> render_click()

      assert has_element?(view, "#clear-database-modal[data-state='closed']")
      refute html =~ "Clearing…"
    end
  end

  describe "refresh image cache — arm in place" do
    test "the first click arms the row rather than refreshing", %{conn: conn} do
      view = open_maintenance_section(conn)

      html =
        view
        |> element("button[phx-click='refresh_image_cache_confirm']")
        |> render_click()

      refute html =~ "Refreshing…"
      # Only the armed row can fire the real thing.
      assert has_element?(view, "button[phx-click='refresh_image_cache'][data-nav-item]")
      assert has_element?(view, "button[phx-click='refresh_image_cache_cancel'][data-nav-item]")
    end

    test "cancelling disarms it", %{conn: conn} do
      view = open_maintenance_section(conn)

      view
      |> element("button[phx-click='refresh_image_cache_confirm']")
      |> render_click()

      view
      |> element("button[phx-click='refresh_image_cache_cancel']")
      |> render_click()

      refute has_element?(view, "button[phx-click='refresh_image_cache']")
      assert has_element?(view, "button[phx-click='refresh_image_cache_confirm']")
    end
  end

  describe "reachability — the reason the native dialog had to go" do
    test "both modal buttons are nav items, so a gamepad can answer", %{conn: conn} do
      view = open_danger_section(conn)

      view
      |> element("button[phx-click='clear_database_prompt']")
      |> render_click()

      assert has_element?(
               view,
               "#clear-database-modal button[phx-click='clear_database'][data-nav-item]"
             )

      assert has_element?(
               view,
               "#clear-database-modal button[phx-click='cancel_clear_database'][data-nav-item]"
             )
    end
  end
end
