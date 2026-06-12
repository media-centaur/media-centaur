defmodule MediaCentaurWeb.SettingsLiveMediaDirsTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Config

  # `SettingsLive.ensure_loaded/1` defers its 15+ config / capability
  # / probe reads to an owned `start_async(:settings_load, …)` (ADR-049).
  # `render_async/1` awaits the load deterministically before tests click
  # edit/save — no wall-clock sleep.
  defp wait_for_async_load(view) do
    _ = render_async(view)
    view
  end

  setup do
    on_exit(fn ->
      :ok = Config.put_media_dirs([])
    end)

    :ok
  end

  test "deep link opens the add dialog", %{conn: conn} do
    {:ok, _view, html} = live_async!(conn, "/settings?section=library&add_media_dir=1")
    assert html =~ "Add media directory"
    assert html =~ "name=\"entry[dir]\""
  end

  test "save persists and closes the dialog", %{conn: conn} do
    tmp = Path.join(System.tmp_dir!(), "wd-save-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, view, _} = live_async!(conn, "/settings?section=library&add_media_dir=1")

    view
    |> form("form[phx-submit='media_dir:save']", entry: %{dir: tmp, name: "Movies", images_dir: ""})
    |> render_change()

    # `media_dir:save` reads dialog.entry/validation, which only the
    # 500ms-debounced validate handler populates. Poll until the preview
    # ("Found N video files…") proves the debounce fired before submitting.
    render_until(view, "video files")

    view
    |> form("form[phx-submit='media_dir:save']", entry: %{dir: tmp, name: "Movies", images_dir: ""})
    |> render_submit()

    assert Enum.map(Config.media_dirs_entries(), & &1["dir"]) == [Path.expand(tmp)]
  end

  test "clears a previously-set name when user empties the field", %{conn: conn} do
    tmp = Path.join(System.tmp_dir!(), "wd-clear-name-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    :ok =
      Config.put_media_dirs([
        %{"id" => "u1", "dir" => Path.expand(tmp), "images_dir" => nil, "name" => "Movies"}
      ])

    {:ok, view, _} = live_async!(conn, "/settings?section=library")
    view = wait_for_async_load(view)

    view |> element("button[phx-click='media_dir:open_edit'][phx-value-id='u1']") |> render_click()

    view
    |> form("form[phx-submit='media_dir:save']", entry: %{dir: tmp, name: "", images_dir: ""})
    |> render_change()

    # Poll for the debounced validation (see "save persists" above) before
    # submitting — the save handler reads the validated dialog entry.
    render_until(view, "video files")

    view
    |> form("form[phx-submit='media_dir:save']", entry: %{dir: tmp, name: "", images_dir: ""})
    |> render_submit()

    assert [%{"name" => nil}] = Config.media_dirs_entries()
  end

  test "duplicate save is rejected", %{conn: conn} do
    tmp = Path.join(System.tmp_dir!(), "wd-dup-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    :ok =
      Config.put_media_dirs([
        %{"id" => "existing", "dir" => Path.expand(tmp), "images_dir" => nil, "name" => nil}
      ])

    {:ok, view, _} = live_async!(conn, "/settings?section=library&add_media_dir=1")

    view
    |> form("form[phx-submit='media_dir:save']", entry: %{dir: tmp, name: "", images_dir: ""})
    |> render_change()

    # The duplicate-dir error surfaces only after the debounced validation
    # fires — poll for it instead of guessing the settle time.
    html = render_until(view, "already configured")
    assert html =~ "already configured"
  end
end
