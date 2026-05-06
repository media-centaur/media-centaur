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
    test "renders the first step by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup")

      assert html =~ "Step 1 of"
      # First step is watch_dirs (per Probes.step_order/0).
      assert html =~ "Watch directories"
    end

    test "renders a specific step from query string", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup?step=mpv")

      assert html =~ "mpv"
      assert html =~ "Step 3 of 6"
    end

    test "unknown step query falls back to step 1", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup?step=bogus")

      assert html =~ "Step 1 of"
    end
  end

  describe "navigation events" do
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
  end

  describe "finish" do
    test "flips setup_wizard_dismissed and redirects to /", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=download_client")

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
