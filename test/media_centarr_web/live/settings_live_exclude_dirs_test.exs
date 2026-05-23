defmodule MediaCentarrWeb.SettingsLiveExcludeDirsTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Config

  # SettingsLive's `ensure_loaded/1` defers its 15+ config / capability
  # / probe reads to an owned `start_async(:settings_load, …)` (ADR-049).
  # `render_async/1` awaits the load deterministically — no wall-clock sleep.
  defp wait_for_async_load(view) do
    _ = render_async(view)
    view
  end

  setup do
    # Tests mutate Config via render_submit → Config.update/2 — that
    # writes to both `:persistent_term` (in-memory) and the DB
    # `settings_entries` table. The sandbox rolls back the DB write
    # per test; only the in-memory cache needs explicit restore here.
    # Previously this on_exit also called `Config.update(:exclude_dirs, [])`,
    # which is a DB write that races under concurrent load because
    # on_exit runs in `ExUnit.OnExitHandler` — a process that doesn't
    # own the test's sandbox connection. The persistent_term put below
    # is pure in-memory ETS and is safe in on_exit.
    original = :persistent_term.get({Config, :config})

    on_exit(fn -> :persistent_term.put({Config, :config}, original) end)

    :ok
  end

  defp tmp_dir(label) do
    path = Path.join(System.tmp_dir!(), "exclude-dir-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  test "adds a valid absolute path that exists on disk", %{conn: conn} do
    tmp = tmp_dir("valid")
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, view, _} = live_async!(conn, "/settings?section=library")

    view
    |> form("form[phx-submit='exclude_dir:add']", %{"path" => tmp})
    |> render_submit()

    assert tmp in Config.get(:exclude_dirs)
    assert render(view) =~ tmp
  end

  test "rejects a relative path (inline error, input preserved, button disabled)", %{conn: conn} do
    {:ok, view, _} = live_async!(conn, "/settings?section=library")

    html =
      view
      |> form("form[phx-submit='exclude_dir:add']", %{"path" => "cache"})
      |> render_change()

    assert html =~ "Must be an absolute path"
    refute "cache" in (Config.get(:exclude_dirs) || [])
  end

  test "rejects a path that doesn't exist on disk", %{conn: conn} do
    {:ok, view, _} = live_async!(conn, "/settings?section=library")

    html =
      view
      |> form("form[phx-submit='exclude_dir:add']", %{
        "path" => "/does/not/exist/#{System.unique_integer([:positive])}"
      })
      |> render_change()

    assert html =~ "Path does not exist"
  end

  test "rejects a duplicate path", %{conn: conn} do
    tmp = tmp_dir("dup")
    on_exit(fn -> File.rm_rf!(tmp) end)

    :ok = Config.update(:exclude_dirs, [tmp])
    {:ok, view, _} = live_async!(conn, "/settings?section=library")
    view = wait_for_async_load(view)

    html =
      view
      |> form("form[phx-submit='exclude_dir:add']", %{"path" => tmp})
      |> render_change()

    assert html =~ "Already in the list"

    view
    |> form("form[phx-submit='exclude_dir:add']", %{"path" => tmp})
    |> render_submit()

    assert Config.get(:exclude_dirs) == [tmp]
  end

  test "deletes an entry", %{conn: conn} do
    tmp_a = tmp_dir("del-a")
    tmp_b = tmp_dir("del-b")

    on_exit(fn ->
      File.rm_rf!(tmp_a)
      File.rm_rf!(tmp_b)
    end)

    :ok = Config.update(:exclude_dirs, [tmp_a, tmp_b])
    {:ok, view, _} = live_async!(conn, "/settings?section=library")
    view = wait_for_async_load(view)

    view
    |> element("button[phx-click='exclude_dir:delete'][phx-value-path='#{tmp_a}']")
    |> render_click()

    assert Config.get(:exclude_dirs) == [tmp_b]
  end
end
