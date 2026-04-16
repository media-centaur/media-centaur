defmodule MediaCentarrWeb.ConsolePageLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Console
  alias MediaCentarr.Console.Filter

  setup do
    :ok = Console.clear()
    :ok = Console.update_filter(Filter.new_with_defaults())
    :ok
  end

  test "mounts at /console", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/console")
    assert html =~ "console-fullpage"
  end

  test "subscribes to Console topic and receives log entries", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    :ok = Console.subscribe()

    require MediaCentarr.Log, as: Log
    Log.warning(:pipeline, "console page integration test")

    assert_receive {:log_entry, %{message: "console page integration test"}}, 500

    rendered = render(view)
    assert rendered =~ "console page integration test"
  end

  test "clear_buffer event empties the buffer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    :ok = Console.subscribe()

    require MediaCentarr.Log, as: Log
    Log.warning(:pipeline, "will be cleared on page")

    assert_receive {:log_entry, %{message: "will be cleared on page"}}, 500

    render_click(view, "clear_buffer")
    assert_receive :buffer_cleared, 500

    assert Console.recent_entries() == []
  end
end
