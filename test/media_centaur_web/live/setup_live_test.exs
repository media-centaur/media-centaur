defmodule MediaCentaurWeb.SetupLiveTest do
  @moduledoc """
  Smoke + key-event tests for the Setup Tour LiveView at `/setup`.
  Exercises mount/render at each step, the save_path event for binary
  probes, and the finish event that flips `setup_wizard_dismissed` and
  redirects to `/`.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Settings.Config

  describe "mount + render" do
    test "renders the welcome step by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup")

      assert html =~ "Step 1 of 8"
      # First step is :welcome.
      assert html =~ "Welcome to Media Centaur"
      assert html =~ "Begin"
    end

    test "renders a specific step from query string", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup?step=mpv")

      assert html =~ "mpv"
      # mpv is step 4 of 8 (welcome=1, media_dirs=2, tmdb=3, mpv=4, ffprobe=5,
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
      assert html =~ "Welcome to Media Centaur"
    end

    test "the step-progress bar reports the current step to assistive tech", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=tmdb")

      assert has_element?(view, "[role='progressbar'][aria-valuenow='3'][aria-valuemax='8']")
    end

    test "step copy is concise — no 'what this is' / 'why it matters' essays", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/setup?step=media_dirs")

      refute html =~ "What this is"
      refute html =~ "Why it matters"
    end

    test "wires the input-nav DOM contract (page behavior + grid zone + nav items)", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=media_dirs")

      assert has_element?(view, "[data-page-behavior='setup'][data-nav-default-zone='setup']")
      assert has_element?(view, "section[data-nav-zone='grid']")
      # The footer Next/Back and the form controls are reachable nav items.
      assert has_element?(view, "[data-nav-zone='grid'] [data-nav-item][tabindex='0']")
    end
  end

  describe "navigation events" do
    test "begin (next on welcome) advances to media_dirs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=welcome")

      view |> element("button", "Begin") |> render_click()

      assert_patch(view, "/setup?step=media_dirs")
    end

    test "next is blocked on a critical unconfigured step (gate refuses, no Skip)", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=media_dirs")

      # No media_dirs configured → probe :not_configured → Gate.check/3
      # returns {:blocked, :probe_not_ok}. media_dirs is critical (not
      # `optional?`) so the Next button is rendered `disabled` AND there
      # is no Skip button — the user must configure a directory before
      # advancing.
      assert_raise ArgumentError, ~r/disabled/, fn ->
        view |> element("button", "Next") |> render_click()
      end

      # Skip is intentionally absent on critical steps.
      refute has_element?(view, "button[phx-click='setup:skip']")
    end

    test "skip advances on an optional unconfigured step", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=prowlarr")

      # Prowlarr is optional → Skip is rendered alongside Next and
      # bypasses the gate regardless of configuration state.
      view |> element("button[phx-click='setup:skip']") |> render_click()
      assert_patch(view, "/setup?step=download_client")
    end

    test "back decrements the step", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=mpv")

      view |> element("button", "Back") |> render_click()

      assert_patch(view, "/setup?step=tmdb")
    end

    test "skip advances like next", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=ffprobe")

      view |> element("button[phx-click='setup:skip']") |> render_click()

      assert_patch(view, "/setup?step=prowlarr")
    end

    test "skip on download_client advances to summary, not finish", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=download_client")

      # download_client is optional + unconfigured → Next is gated.
      # Skip moves to the summary step, which is the natural end of the
      # wizard. (Pre-gate this test clicked Next; the renaming reflects
      # the new design where Next means "configured and ready".)
      view |> element("button[phx-click='setup:skip']") |> render_click()

      assert_patch(view, "/setup?step=summary")
    end
  end

  describe "finish" do
    test "flips setup_wizard_dismissed and redirects to /library from summary", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=summary")

      # Tour lands on /library (not /) so the user sees the empty-state
      # scan affordance + pipeline-activity indicator while ingest
      # finishes draining the files the watcher just dispatched.
      assert {:error, {:live_redirect, %{to: "/library"}}} =
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

  describe "media directories step" do
    setup do
      dir = System.tmp_dir!()
      :ok = Config.put_media_dirs([%{"id" => "dir-a", "dir" => dir}])
      %{dir: dir}
    end

    test "the cursor enters the step on the add field, not on a Remove", %{conn: conn} do
      # Regression: the first nav item in the card was the first directory's
      # Remove, so pressing OK on Welcome's Begin landed on it.
      {:ok, view, _html} = live(conn, "/setup?step=media_dirs")

      [first | _] =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("[data-nav-zone='grid'] [data-nav-item]")
        |> Enum.to_list()

      assert LazyHTML.attribute(first, "name") == ["dir"]
    end

    test "Remove arms on the first press and removes on the second", %{conn: conn, dir: dir} do
      {:ok, view, _html} = live(conn, "/setup?step=media_dirs")

      view |> element("button[phx-click='setup:remove_media_dir']") |> render_click()

      assert Enum.map(Config.media_dirs_entries(), & &1["dir"]) == [dir]
      assert has_element?(view, "button[phx-click='setup:remove_media_dir'][data-armed]")

      view |> element("button[phx-click='setup:remove_media_dir']") |> render_click()

      assert Config.media_dirs_entries() == []
    end
  end

  describe "integration step fields" do
    test "each field's label names its input", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=prowlarr")

      for name <- ["prowlarr_url", "prowlarr_api_key"] do
        assert has_element?(view, "label[for='setup-#{name}']")
        assert has_element?(view, "input#setup-#{name}[name='#{name}'][data-nav-item]")
      end
    end

    test "the download client type is stated, not a one-option select", %{conn: conn} do
      {:ok, view, html} = live(conn, "/setup?step=download_client")

      assert has_element?(view, "input[type='hidden'][name='download_client_type'][value='qbittorrent']")
      assert html =~ "qBittorrent"
    end
  end

  describe "escaping the tour" do
    test "the media directories step still blocks Next", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=media_dirs")

      # Required means required — this is the behaviour Skip the tour works
      # around rather than removes.
      assert has_element?(view, "button[phx-click='setup:next'][disabled]")
      refute has_element?(view, "button[phx-click='setup:skip']")
    end

    test "Skip the tour reaches the summary from a blocked required step", %{conn: conn} do
      # Regression: with no media directory and no TMDB key, Next was disabled,
      # neither required step offered Skip, and the page carried no links at
      # all — the reader could not enter the app by any route.
      {:ok, view, _html} = live(conn, "/setup?step=media_dirs")

      html = view |> element("button[phx-click='setup:skip_tour']") |> render_click()

      assert html =~ "Setup summary"
      assert html =~ "required steps are still incomplete"
    end

    test "the summary offers no Skip the tour — it is already the way out", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=summary")

      refute has_element?(view, "button[phx-click='setup:skip_tour']")
      assert has_element?(view, "button[phx-click='setup:next']", "Finish")
    end

    test "Skip the tour is reachable by keyboard and gamepad — a nav item in its own zone", %{
      conn: conn
    } do
      # Regression: it was a nav item outside every zone, so a remote or
      # gamepad user missing a required step had no way off the page.
      {:ok, view, _html} = live(conn, "/setup?step=tmdb")

      assert has_element?(
               view,
               "[data-nav-zone='toolbar'] button[phx-click='setup:skip_tour'][data-nav-item]"
             )
    end

    test "Finish from the summary works with required steps incomplete", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/setup?step=summary")

      assert {:error, {:live_redirect, %{to: "/library"}}} =
               view |> element("button[phx-click='setup:next']", "Finish") |> render_click()

      assert Config.get(:setup_wizard_dismissed) == true
    end
  end
end
