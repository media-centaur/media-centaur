defmodule MediaCentaurWeb.ConsolePageLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Console
  alias MediaCentaur.Console.Filter

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

    require MediaCentaur.Log, as: Log
    Log.warning(:pipeline, "console page integration test")

    await_log_broadcast(["console page integration test"])

    rendered = render(view)
    assert rendered =~ "console page integration test"
  end

  test "clear_buffer event empties the buffer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    :ok = Console.subscribe()

    require MediaCentaur.Log, as: Log
    Log.warning(:pipeline, "will be cleared on page")

    await_log_broadcast(["will be cleared on page"])

    render_click(view, "clear_buffer")
    assert_receive :buffer_cleared, 500

    assert Console.recent_entries() == []
  end

  # Batched broadcast contract (instant-navigation P5): appends arrive as
  # {:log_entries, entries} flushes, possibly several messages per batch.
  # Collect batches until every expected message has been seen.
  defp await_log_broadcast(messages, seen \\ []) when is_list(messages) do
    seen_messages = Enum.map(seen, & &1.message)

    if messages -- seen_messages == [] do
      :ok
    else
      assert_receive {:log_entries, entries}, 500
      await_log_broadcast(messages, seen ++ entries)
    end
  end
end
