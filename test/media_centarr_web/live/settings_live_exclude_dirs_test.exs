defmodule MediaCentarrWeb.SettingsLiveExcludeDirsTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Config

  setup do
    original = :persistent_term.get({Config, :config})

    on_exit(fn ->
      :ok = Config.update(:exclude_dirs, [])
      :persistent_term.put({Config, :config}, original)
    end)

    :ok
  end

  test "adds a valid absolute path", %{conn: conn} do
    {:ok, view, _} = live(conn, "/settings?section=library")

    view
    |> form("form[phx-submit='exclude_dir:add']", %{"path" => "/mnt/cache"})
    |> render_submit()

    assert "/mnt/cache" in Config.get(:exclude_dirs)
    assert render(view) =~ "/mnt/cache"
  end

  test "rejects a relative path", %{conn: conn} do
    {:ok, view, _} = live(conn, "/settings?section=library")

    view
    |> form("form[phx-submit='exclude_dir:add']", %{"path" => "cache"})
    |> render_submit()

    refute "cache" in (Config.get(:exclude_dirs) || [])
  end

  test "rejects a duplicate", %{conn: conn} do
    :ok = Config.update(:exclude_dirs, ["/mnt/cache"])
    {:ok, view, _} = live(conn, "/settings?section=library")

    view
    |> form("form[phx-submit='exclude_dir:add']", %{"path" => "/mnt/cache"})
    |> render_submit()

    assert Config.get(:exclude_dirs) == ["/mnt/cache"]
  end

  test "deletes an entry", %{conn: conn} do
    :ok = Config.update(:exclude_dirs, ["/mnt/cache", "/mnt/trash"])
    {:ok, view, _} = live(conn, "/settings?section=library")

    view
    |> element("button[phx-click='exclude_dir:delete'][phx-value-path='/mnt/cache']")
    |> render_click()

    assert Config.get(:exclude_dirs) == ["/mnt/trash"]
  end
end
