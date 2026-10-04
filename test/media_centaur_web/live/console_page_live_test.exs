defmodule MediaCentaurWeb.ConsolePageLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Console
  alias MediaCentaur.Console.Entry
  alias MediaCentaur.Console.Filter

  setup do
    :ok = Console.clear()
    :ok = Console.update_filter(Filter.new_with_defaults())
    :ok
  end

  test "mounts at /console", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")
    assert has_element?(view, "#console-page")
  end

  test "sits in the app shell, with Status marked as where it belongs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    assert has_element?(view, "[data-nav-zone='sidebar']")
    assert has_element?(view, ~s|.sidebar-link-active[href="/status"]|)
    assert has_element?(view, "[data-nav-default-zone='console']")
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

  test "initial mount streams only entries the persisted filter admits", %{conn: conn} do
    # The default filter hides framework components (:phoenix/:ecto/:live_view).
    # Seed the buffer with one admitted (app) and one excluded (framework) entry
    # BEFORE mounting, so both sit in the snapshot the connected mount reads. The
    # buggy mount streamed the raw window unfiltered, so the excluded entry
    # briefly painted before live entries scrolled it away — the "flash of
    # unfiltered text". Mount must apply the filter, like every other
    # entry-producing path (new-entry insert, filter change, buffer resize).
    seed([entry(:pipeline, "admitted app entry"), entry(:phoenix, "excluded framework entry")])

    {:ok, _view, html} = live(conn, ~p"/console")

    assert html =~ "admitted app entry"
    refute html =~ "excluded framework entry"
  end

  test "a live line is appended after the lines already shown", %{conn: conn} do
    seed([entry(:pipeline, "earlier line")])
    {:ok, view, _html} = live(conn, ~p"/console")

    :ok = Console.subscribe()
    require MediaCentaur.Log, as: Log
    Log.warning(:pipeline, "later line")
    await_log_broadcast(["later line"])

    messages =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#console-rows .console-message")
      |> Enum.map(&LazyHTML.text/1)

    assert messages == ["earlier line", "later line"]
  end

  describe "scoped to a subsystem" do
    test "shows only that subsystem's lines", %{conn: conn} do
      seed([entry(:library, "library line"), entry(:pipeline, "pipeline line")])

      {:ok, view, html} = live(conn, ~p"/console?subsystem=library")

      assert html =~ "library line"
      refute html =~ "pipeline line"
      assert has_element?(view, ~s|a[href="/console"]|, "Show all logs")
      assert has_element?(view, ~s|a[href="/status?subsystem=library"]|)
    end

    test "filter edits stay with this visit and leave the saved filter alone", %{conn: conn} do
      saved = Console.get_filter()
      seed([entry(:pipeline, "pipeline line")])
      {:ok, view, _html} = live(conn, ~p"/console?subsystem=library")

      render_click(view, "toggle_component", %{"component" => "pipeline"})

      assert render(view) =~ "pipeline line"
      assert Console.get_filter() == saved
    end

    test "ignores saved-filter changes made elsewhere", %{conn: conn} do
      seed([entry(:pipeline, "pipeline line")])
      {:ok, view, _html} = live(conn, ~p"/console?subsystem=library")

      :ok = Console.update_filter(Filter.new(default_component: :show, level: :info))

      refute render(view) =~ "pipeline line"
    end

    test "patching to /console returns to the saved filter", %{conn: conn} do
      seed([entry(:pipeline, "pipeline line")])
      {:ok, view, _html} = live(conn, ~p"/console?subsystem=library")

      html = render_patch(view, ~p"/console")

      assert html =~ "pipeline line"
      refute has_element?(view, "a", "Show all logs")
    end
  end

  test "clear_buffer event empties the buffer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    # `:buffer_cleared` arrives on the Console topic, not from the view.
    :ok = Console.subscribe()
    seed([entry(:pipeline, "will be cleared on page")])

    render_click(view, "clear_buffer")
    assert_receive :buffer_cleared, 500

    assert whole_store() == []
  end

  test "showing a hidden component redraws the stream from its ring", %{conn: conn} do
    # :phoenix is hidden by the default filter, so its ring is not read at mount.
    seed([entry(:phoenix, "framework entry")])

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

    seed([entry(:pipeline, "survives a resize")])

    # Resize to the cap the store already has: the redraw path runs in full
    # without leaving a changed cap behind for the next test.
    cap = Console.config().cap
    render_click(view, "resize_buffer", %{"size" => Integer.to_string(cap)})

    assert render(view) =~ "survives a resize"
  end

  test "download_buffer pushes the visible log as a named file", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    seed([entry(:pipeline, "downloadable entry")])

    render_click(view, "download_buffer")

    assert_push_event(view, "console:download", %{filename: filename, content: content})
    assert filename =~ "media-centaur-"
    assert content =~ "downloadable entry"
  end

  test "copy_visible pushes the visible log as clipboard text", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    seed([entry(:pipeline, "copyable entry")])

    render_click(view, "copy_visible")

    assert_push_event(view, "console:copy", %{content: content})
    assert content =~ "copyable entry"
  end

  # Regression: the search was held twice — the browser hid rows, the
  # Buffer kept a copy for copy/download — and `Logic.set_search/2` never
  # refreshed the copy's lowercase cache, so copy and download matched a
  # stale query. The browser owns the query now and sends it with the act.
  test "copy and download hand over the lines matching the browser's query", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    seed([entry(:pipeline, "alpha line"), entry(:pipeline, "beta line")])

    render_click(view, "copy_visible", %{"search" => "ALPHA"})
    assert_push_event(view, "console:copy", %{content: copied})
    assert copied =~ "alpha line"
    refute copied =~ "beta line"

    render_click(view, "download_buffer", %{"search" => "beta"})
    assert_push_event(view, "console:download", %{content: downloaded})
    assert downloaded =~ "beta line"
    refute downloaded =~ "alpha line"
  end

  test "the server holds no text search: typing sends nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    refute has_element?(view, "#console-search-input[phx-keyup]")
    refute has_element?(view, "#console-search-input[phx-change]")
  end

  defp entry(component, message) do
    %Entry{
      id: System.unique_integer([:monotonic, :positive]),
      timestamp: ~U[2026-09-17 10:00:00Z],
      level: :info,
      component: component,
      message: message
    }
  end

  # Seeds the store the way the console handler does, without going through
  # Logger: a `Log.warning` would also mint an ErrorReports incident whose
  # `{:buckets_changed, _}` broadcast lands in whichever test is running when
  # the Buckets server gets to it. The one test that must exercise the real
  # Logger path keeps `Log.warning` and awaits the broadcast.
  defp seed(entries) do
    Enum.each(entries, &Console.Buffer.append/1)
    :ok = Console.flush()
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
