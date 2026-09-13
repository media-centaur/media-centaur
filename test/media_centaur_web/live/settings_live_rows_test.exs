defmodule MediaCentaurWeb.SettingsLiveRowsTest do
  @moduledoc """
  The save-on-the-act rows of the Library and Playback sections
  (UIDR-041 §2): a text row commits on blur, a stepper persists the
  absolute rung it carries, and a no-op stays quiet.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Settings.Config

  setup do
    Config.update(:file_absence_ttl_days, 30)
    Config.update(:recent_changes_days, 3)
    Config.update(:mpv_socket_timeout_ms, 5000)
    :ok
  end

  describe "library" do
    test "the data directory commits on blur", %{conn: conn} do
      dir = Path.join(System.tmp_dir!(), "rows-test-#{System.unique_integer([:positive])}")
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=library")

      view |> element("#data-dir input[name=data_dir]") |> render_blur(%{"value" => dir})

      assert Config.get(:data_dir) == dir
    end

    test "the absence window steps along its ladder and resets", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=library")

      view
      |> element("#absence-ttl button[aria-label=\"Increase Keep a missing file's entry for\"]")
      |> render_click()

      assert Config.get(:file_absence_ttl_days) == 45

      view
      |> element("#absence-ttl button[aria-label=\"Reset Keep a missing file's entry for\"]")
      |> render_click()

      assert Config.get(:file_absence_ttl_days) == 30
    end

    test "the recent-changes window steps down to one day and stops", %{conn: conn} do
      Config.update(:recent_changes_days, 2)
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=library")
      decrease = "#recent-changes button[aria-label='Decrease Recent changes window']"

      view |> element(decrease) |> render_click()
      assert Config.get(:recent_changes_days) == 1

      view |> element(decrease) |> render_click()
      assert Config.get(:recent_changes_days) == 1
    end
  end

  describe "playback" do
    test "the socket timeout steps along its ladder", %{conn: conn} do
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=playback")

      view
      |> element("#mpv-socket-timeout button[aria-label='Increase Socket timeout']")
      |> render_click()

      assert Config.get(:mpv_socket_timeout_ms) == 7500
    end

    test "the mpv path commits on blur and ignores a blank", %{conn: conn} do
      before = Config.get(:mpv_path)
      {:ok, view, _} = live_async!(conn, ~p"/settings?section=playback")

      view |> element("#mpv-path input[name=mpv_path]") |> render_blur(%{"value" => ""})
      assert Config.get(:mpv_path) == before

      view |> element("#mpv-path input[name=mpv_path]") |> render_blur(%{"value" => "/opt/mpv/bin/mpv"})
      assert Config.get(:mpv_path) == "/opt/mpv/bin/mpv"
    end
  end
end
