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

    assert whole_store() == []
  end

  test "showing a hidden component redraws the stream from its ring", %{conn: conn} do
    :ok = Console.subscribe()

    require MediaCentaur.Log, as: Log
    # :phoenix is hidden by the default filter, so its ring is not read at mount.
    Log.warning(:phoenix, "framework entry")

    await_log_broadcast(["framework entry"])

    {:ok, view, html} = live(conn, ~p"/console")
    refute html =~ "framework entry"

    render_click(view, "toggle_component", %{"component" => "phoenix"})

    # The filter update is a call into the buffer made from the LiveView's own
    # process, so the {:filter_changed, _} broadcast is already queued behind
    # this handle_event when render/1 arrives — no settle wait needed.
    assert render(view) =~ "framework entry"
  end

  test "a buffer resize redraws the stream from the store", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    :ok = Console.subscribe()

    require MediaCentaur.Log, as: Log
    Log.warning(:pipeline, "survives a resize")

    await_log_broadcast(["survives a resize"])

    # Resize to the cap the store already has: the redraw path runs in full
    # without leaving a changed cap behind for the next test.
    cap = Console.config().cap
    render_click(view, "resize_buffer", %{"size" => Integer.to_string(cap)})

    assert render(view) =~ "survives a resize"
  end

  test "download_buffer pushes the visible log as a named file", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    :ok = Console.subscribe()

    require MediaCentaur.Log, as: Log
    Log.warning(:pipeline, "downloadable entry")

    await_log_broadcast(["downloadable entry"])

    render_click(view, "download_buffer")

    assert_push_event(view, "console:download", %{filename: filename, content: content})
    assert filename =~ "media-centaur-"
    assert content =~ "downloadable entry"
  end

  test "copy_visible pushes the visible log as clipboard text", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    :ok = Console.subscribe()

    require MediaCentaur.Log, as: Log
    Log.warning(:pipeline, "copyable entry")

    await_log_broadcast(["copyable entry"])

    render_click(view, "copy_visible")

    assert_push_event(view, "console:copy", %{content: content})
    assert content =~ "copyable entry"
  end

  # Everything the store holds, unfiltered. `Filter.all()` is the read
  # selector that admits every component and level; the limit is well above
  # the per-component cap these tests ever fill.
  defp whole_store, do: Console.read(Filter.all(), 1_000)

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
