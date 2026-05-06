defmodule MediaCentarrWeb.SetupLiveTest do
  @moduledoc """
  Smoke + key-event tests for the Setup Tour LiveView at `/setup`.
  Exercises mount/render at each step, the save_path event for binary
  probes, and the finish event that flips `setup_wizard_dismissed` and
  redirects to `/`.
  """

  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Config

  setup do
    original = :persistent_term.get({Config, :config})

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original)
    end)

    :ok
  end

  describe "mount + render" do
    test "renders the welcome step by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup")

      assert html =~ "Step 1 of 8"
      # First step is :welcome.
      assert html =~ "Welcome to Media Centarr"
      assert html =~ "Begin"
    end

    test "renders a specific step from query string", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup?step=mpv")

      assert html =~ "mpv"
      # mpv is step 4 of 8 (welcome=1, watch_dirs=2, tmdb=3, mpv=4, ffprobe=5,
      # prowlarr=6, download_client=7, summary=8).
      assert html =~ "Step 4 of 8"
    end

    test "renders the summary step", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup?step=summary")

      assert html =~ "Setup summary"
      assert html =~ "Step 8 of 8"
      assert html =~ "Finish"
    end

    test "unknown step query falls back to welcome", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup?step=bogus")

      assert html =~ "Step 1 of 8"
      assert html =~ "Welcome to Media Centarr"
    end
  end

  describe "navigation events" do
    test "begin (next on welcome) advances to watch_dirs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=welcome")

      view |> element("button", "Begin") |> render_click()

      assert_patch(view, "/setup?step=watch_dirs")
    end

    test "next advances the step in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=watch_dirs")

      view |> element("button", "Next") |> render_click()

      assert_patch(view, "/setup?step=tmdb")
    end

    test "back decrements the step", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=mpv")

      view |> element("button", "Back") |> render_click()

      assert_patch(view, "/setup?step=tmdb")
    end

    test "skip advances like next", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=ffprobe")

      view |> element("button", "Skip") |> render_click()

      assert_patch(view, "/setup?step=prowlarr")
    end

    test "next on download_client advances to summary, not finish", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=download_client")

      view |> element("button", "Next") |> render_click()

      assert_patch(view, "/setup?step=summary")
    end
  end

  describe "finish" do
    test "flips setup_wizard_dismissed and redirects to / from summary", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=summary")

      assert {:error, {:live_redirect, %{to: "/"}}} =
               view |> element("button", "Finish") |> render_click()

      assert Config.get(:setup_wizard_dismissed) == true
    end
  end

  describe "save_path event (binary steps)" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "setup_live_#{Ecto.UUID.generate()}")
      File.mkdir_p!(tmp_dir)
      executable = Path.join(tmp_dir, "fake-mpv")
      File.write!(executable, "#!/bin/sh\nexit 0\n")
      File.chmod!(executable, 0o755)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{executable: executable}
    end

    test "save_path persists the path to Config", %{conn: conn, executable: executable} do
      {:ok, view, _html} = live(conn, "/setup?step=mpv")

      view
      |> form("form", path: executable)
      |> render_submit()

      assert Config.get(:mpv_path) == executable
    end
  end
end
