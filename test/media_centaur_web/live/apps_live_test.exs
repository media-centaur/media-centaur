defmodule MediaCentaurWeb.AppsLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Apps

  # Artwork writes (steam adds, app removal) must land in a tmp data_dir,
  # never in the working tree (ADR-016).
  setup do
    data_dir = Path.join(System.tmp_dir!(), "mc-apps-live-#{System.unique_integer([:positive])}")
    File.mkdir_p!(data_dir)

    original = :persistent_term.get({MediaCentaur.Settings.Config, :config}, %{})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      Map.put(original, :data_dir, data_dir)
    )

    on_exit(fn ->
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, original)
      File.rm_rf!(data_dir)
    end)

    :ok
  end

  describe "grid" do
    test "renders every app as a card", %{conn: conn} do
      app = create_app(%{name: "Sample Game"})
      {:ok, view, _html} = live(conn, "/apps")

      assert has_element?(view, "[data-app-id='#{app.id}']")
    end

    test "empty state points at Manage", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/apps")
      assert html =~ "No apps yet"
    end
  end

  describe "manage mode" do
    test "toggles remove affordance on cards", %{conn: conn} do
      app = create_app(%{})
      {:ok, view, _html} = live(conn, "/apps")

      refute has_element?(view, "[phx-click='remove_app']")
      view |> element("[phx-click='toggle_manage']") |> render_click()
      assert has_element?(view, "[phx-click='remove_app'][phx-value-app-id='#{app.id}']")
    end

    test "remove_app deletes the app", %{conn: conn} do
      app = create_app(%{})
      {:ok, view, _html} = live(conn, "/apps")

      view |> element("[phx-click='toggle_manage']") |> render_click()
      view |> element("[phx-click='remove_app'][phx-value-app-id='#{app.id}']") |> render_click()

      assert Apps.list_apps() == []
      refute has_element?(view, "[data-app-id='#{app.id}']")
    end
  end

  describe "manual add" do
    test "save_manual creates an app and closes the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/apps")

      view |> element("[phx-click='toggle_manage']") |> render_click()
      view |> element("[phx-click='open_add']") |> render_click()
      view |> element("[phx-click='set_add_tab'][phx-value-tab='manual']") |> render_click()

      view
      |> form("#app-manual-form", app: %{name: "Sample App", command: "sample-app"})
      |> render_submit()

      assert [app] = Apps.list_apps()
      assert app.origin == %{"source" => "manual"}
      assert has_element?(view, "[data-app-id='#{app.id}']")
    end

    test "invalid manual form re-renders with errors and saves nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/apps")

      view |> element("[phx-click='toggle_manage']") |> render_click()
      view |> element("[phx-click='open_add']") |> render_click()
      view |> element("[phx-click='set_add_tab'][phx-value-tab='manual']") |> render_click()

      html =
        view
        |> form("#app-manual-form", app: %{name: "", command: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Apps.list_apps() == []
    end
  end

  describe "edit" do
    test "edit_app opens the form prefilled and save updates", %{conn: conn} do
      app = create_app(%{name: "Old Name", command: "old-cmd"})
      {:ok, view, _html} = live(conn, "/apps")

      view |> element("[phx-click='toggle_manage']") |> render_click()
      view |> element("[phx-click='edit_app'][phx-value-app-id='#{app.id}']") |> render_click()

      view
      |> form("#app-manual-form", app: %{name: "New Name", command: "new-cmd"})
      |> render_submit()

      assert Apps.get_app!(app.id).name == "New Name"
    end
  end

  describe "steam picker" do
    test "lists discovered games, adds on click, marks added games", %{conn: conn} do
      root = Path.join(System.tmp_dir!(), "mc-steam-live-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "steamapps"))

      for {id, name} <- [{100, "Sample Game"}, {200, "Other Game"}] do
        File.write!(Path.join([root, "steamapps", "appmanifest_#{id}.acf"]), """
        "AppState"
        {
        \t"appid"\t\t"#{id}"
        \t"name"\t\t"#{name}"
        }
        """)

        cache = Path.join([root, "appcache", "librarycache", "#{id}"])
        File.mkdir_p!(cache)
        File.write!(Path.join(cache, "header.jpg"), "jpg")
        File.write!(Path.join(cache, "library_600x900.jpg"), "jpg")
      end

      on_exit(fn -> File.rm_rf!(root) end)

      {:ok, view, _html} = live(conn, "/apps?steam_root=#{URI.encode_www_form(root)}")

      view |> element("[phx-click='toggle_manage']") |> render_click()
      view |> element("[phx-click='open_add']") |> render_click()

      assert has_element?(view, "[phx-click='add_steam_game'][phx-value-app-id='100']")

      view |> element("[phx-click='add_steam_game'][phx-value-app-id='100']") |> render_click()

      assert [app] = Apps.list_apps()
      assert app.origin == %{"source" => "steam", "app_id" => 100}
      assert has_element?(view, "[data-steam-added='100']")
      refute has_element?(view, "[phx-click='add_steam_game'][phx-value-app-id='100']")
    end

    test "steam absent shows the manual-tab hint", %{conn: conn} do
      missing = Path.join(System.tmp_dir!(), "mc-steam-none-#{System.unique_integer([:positive])}")

      {:ok, view, _html} = live(conn, "/apps?steam_root=#{URI.encode_www_form(missing)}")

      view |> element("[phx-click='toggle_manage']") |> render_click()
      html = view |> element("[phx-click='open_add']") |> render_click()

      assert html =~ "Steam wasn&#39;t found"
    end
  end

  describe "launch" do
    test "launch_app flashes an acknowledgment", %{conn: conn} do
      app = create_app(%{name: "Sample Game", command: "true"})
      {:ok, view, _html} = live(conn, "/apps")

      view |> element("[phx-click='launch_app'][phx-value-app-id='#{app.id}']") |> render_click()
      assert render(view) =~ "Launching Sample Game"
    end
  end

  describe "sidebar entry" do
    test "hidden by default, shown when the preference is on", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/apps")
      refute has_element?(view, "[data-tip='Apps']")

      MediaCentaur.Settings.find_or_create_entry!(%{
        key: MediaCentaur.Settings.Preferences.AppsVisibility.setting_key(),
        value: %{"enabled" => true}
      })

      {:ok, view, _html} = live(conn, "/apps")
      assert has_element?(view, "[data-tip='Apps']")
    end
  end
end
