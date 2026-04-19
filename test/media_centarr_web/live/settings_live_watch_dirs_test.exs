defmodule MediaCentarrWeb.SettingsLiveWatchDirsTest do
  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Config

  setup do
    on_exit(fn ->
      :ok = Config.put_watch_dirs([])
    end)

    :ok
  end

  test "deep link opens the add dialog", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings?section=library&add_watch_dir=1")
    assert html =~ "Add watch directory"
    assert html =~ "name=\"entry[dir]\""
  end

  test "save persists and closes the dialog", %{conn: conn} do
    tmp = Path.join(System.tmp_dir!(), "wd-save-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, view, _} = live(conn, "/settings?section=library&add_watch_dir=1")

    view
    |> form("form[phx-submit='watch_dir:save']", entry: %{dir: tmp, name: "Movies", images_dir: ""})
    |> render_change()

    # Wait for debounced validation (500ms debounce + buffer)
    :timer.sleep(600)

    view
    |> form("form[phx-submit='watch_dir:save']", entry: %{dir: tmp, name: "Movies", images_dir: ""})
    |> render_submit()

    assert Enum.map(Config.watch_dirs_entries(), & &1["dir"]) == [Path.expand(tmp)]
  end

  test "duplicate save is rejected", %{conn: conn} do
    tmp = Path.join(System.tmp_dir!(), "wd-dup-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    :ok =
      Config.put_watch_dirs([
        %{"id" => "existing", "dir" => Path.expand(tmp), "images_dir" => nil, "name" => nil}
      ])

    {:ok, view, _} = live(conn, "/settings?section=library&add_watch_dir=1")

    view
    |> form("form[phx-submit='watch_dir:save']", entry: %{dir: tmp, name: "", images_dir: ""})
    |> render_change()

    :timer.sleep(600)

    html = render(view)
    assert html =~ "already configured"
  end
end
