defmodule MediaCentaurWeb.ConsoleLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Console
  alias MediaCentaur.Console.Filter

  setup do
    # Use the Console facade (ADR-026) — these test pre-conditions run
    # through the same public API a LiveView would.
    :ok = Console.clear()
    :ok = Console.update_filter(Filter.new_with_defaults())
    :ok
  end

  # Helper to get the ConsoleLive sticky child from the parent page.
  defp console_child(parent_view) do
    find_live_child(parent_view, "console-sticky")
  end

  # Poll-with-deadline on a deterministic predicate (ADR-049 — never a fixed
  # settle sleep). Used to wait for an async-logged entry to actually land in
  # the global buffer before forcing its batch out.
  defp wait_until(fun, deadline_ms \\ 2_000)

  defp wait_until(_fun, deadline_ms) when deadline_ms <= 0,
    do: flunk("wait_until: predicate never became true")

  defp wait_until(fun, deadline_ms) do
    if fun.(), do: :ok, else: Process.sleep(10) && wait_until(fun, deadline_ms - 10)
  end

  test "mounts when navigating to the home page (sticky child)", %{conn: conn} do
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

    require MediaCentaur.Log, as: Log
    # Use :warning so the entry passes the test config logger level floor (:warning).
    # Log.info calls are dropped at the Logger level in test config.
    Log.warning(:pipeline, "integration test entry")

    # Log.warning routes through Logger (async, a different process) and the
    # buffer batches broadcasts on a ~100ms window — both wall-clock-sensitive
    # under full-suite load (the source of a pre-existing flake). Wait until the
    # entry has actually landed in the (global) buffer, then force the batch out,
    # so the broadcast and the LV re-render below are deterministic.
    wait_until(fn ->
      Enum.any?(Console.snapshot().entries, &(&1.message == "integration test entry"))
    end)

    :ok = Console.flush()

    await_log_broadcast(["integration test entry"])

    rendered = render(console)
    assert rendered =~ "pipeline"
    assert rendered =~ "integration test entry"
  end

  test "initial mount streams only entries the persisted filter admits", %{conn: conn} do
    # The default filter hides framework components (:phoenix/:ecto/:live_view).
    # Seed the buffer with one admitted (app) and one excluded (framework) entry
    # BEFORE mounting, so both sit in the snapshot the connected mount reads. The
    # buggy mount streamed the raw window unfiltered, so the excluded entry
    # briefly painted before live entries scrolled it away — the "flash of
    # unfiltered text". Mount must apply the filter, like every other
    # entry-producing path (new-entry insert, filter change, buffer resize).
    :ok = Console.subscribe()

    require MediaCentaur.Log, as: Log
    # :warning so both clear the test logger floor — :info is dropped in test config.
    Log.warning(:pipeline, "admitted app entry")
    Log.warning(:phoenix, "excluded framework entry")

    # Once the broadcasts land, the entries are in the buffer: the append cast is
    # processed before the later snapshot_window call (same GenServer, serialized).
    await_log_broadcast(["admitted app entry", "excluded framework entry"])

    {:ok, parent_view, _html} = live(conn, ~p"/")
    rendered = render(console_child(parent_view))

    assert rendered =~ "admitted app entry"
    refute rendered =~ "excluded framework entry"
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

    require MediaCentaur.Log, as: Log
    Log.warning(:pipeline, "will be cleared")

    # Wait deterministically for the entry to land in the buffer.
    await_log_broadcast(["will be cleared"])

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
