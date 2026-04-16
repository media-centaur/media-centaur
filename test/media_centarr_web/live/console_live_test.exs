defmodule MediaCentarrWeb.ConsoleLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Console
  alias MediaCentarr.Console.Filter

  setup do
    # Use the Console facade (ADR-026) — these test pre-conditions run
    # through the same public API a LiveView would.
    :ok = Console.clear()
    :ok = Console.update_filter(Filter.new_with_defaults())
    :ok
  end

  # Helper to get the ConsoleLive sticky child from the parent LibraryLive.
  defp console_child(parent_view) do
    find_live_child(parent_view, "console-sticky")
  end

  test "mounts when navigating to the library page (sticky child)", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "console-sticky-root"
  end

  test "stream receives a new log entry from PubSub", %{conn: conn} do
    {:ok, parent_view, _html} = live(conn, ~p"/")
    console = console_child(parent_view)

    # Subscribe the test process to the same topic the LiveView is on, so
    # we can synchronously wait for the entry to land in the buffer before
    # re-rendering. No Process.sleep — the assert_receive is deterministic.
    :ok = Console.subscribe()

    require MediaCentarr.Log, as: Log
    # Use :warning so the entry passes the test config logger level floor (:warning).
    # Log.info calls are dropped at the Logger level in test config.
    Log.warning(:pipeline, "integration test entry")

    assert_receive {:log_entry, %{message: "integration test entry"}}, 500

    rendered = render(console)
    assert rendered =~ "pipeline"
    assert rendered =~ "integration test entry"
  end

  test "toggle_pause flips the pause state", %{conn: conn} do
    {:ok, parent_view, _html} = live(conn, ~p"/")
    console = console_child(parent_view)

    render_click(console, "toggle_pause")

    assert render(console) =~ "resume"
  end

  test "clear_buffer empties the buffer", %{conn: conn} do
    {:ok, parent_view, _html} = live(conn, ~p"/")
    console = console_child(parent_view)

    :ok = Console.subscribe()

    require MediaCentarr.Log, as: Log
    Log.warning(:pipeline, "will be cleared")

    # Wait deterministically for the entry to land in the buffer.
    assert_receive {:log_entry, %{message: "will be cleared"}}, 500

    render_click(console, "clear_buffer")

    # Wait for the :buffer_cleared broadcast before asserting emptiness.
    assert_receive :buffer_cleared, 500

    assert Console.recent_entries() == []
  end

  test "sticky drawer is not rendered on /console", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/console")
    # The sticky drawer's root div should not appear on the console page.
    # ConsolePageLive uses .console-fullpage, not console-sticky-root.
    refute html =~ "console-sticky-root"
    assert html =~ "console-fullpage"
  end
end
