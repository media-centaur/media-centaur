defmodule MediaCentarrWeb.LibraryLiveAvailabilityTest do
  @moduledoc """
  End-to-end coverage for the "storage unmounted → placeholder tiles +
  banner" chain. Drives the flow through the real PubSub channels used
  in production (`Topics.dir_state/0` → `Library.Availability` GenServer
  → `"library:availability"` topic → `LibraryLive.handle_info/2`).
  """

  use MediaCentarrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentarr.Library.Availability

  # Replays the watcher's broadcast format so we exercise the real
  # GenServer path without needing a drive unmount. The public
  # `__sync_for_test__/0` call guarantees the message has been
  # processed (and the re-broadcast sent) before we return.
  defp broadcast_dir_state(dir, state) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.dir_state(),
      {:dir_state_changed, dir, :watch_dir, state}
    )

    :ok = Availability.__sync_for_test__()
  end

  # Forces a LiveView re-render and waits for any pending messages
  # in its mailbox to process. `render/1` sends a sync message through
  # the LiveView channel machinery — by the time it returns, prior
  # messages have been handled.
  defp render_after_broadcasts(view), do: render(view)

  setup do
    :ok = Availability.__reset_for_test__()
    on_exit(fn -> Availability.__reset_for_test__() end)
    :ok
  end

  describe "offline banner" do
    test "not shown when every dir is :watching", %{conn: conn} do
      broadcast_dir_state("/mnt/videos", :watching)
      {:ok, _view, html} = live(conn, ~p"/library")

      refute html =~ "Storage offline"
      refute html =~ "temporarily unavailable"
    end

    test "not shown when dir_status is empty (fresh install)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/library")

      refute html =~ "Storage offline"
    end

    test "shown with a single-dir message when one dir flips to :unavailable", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/library")
      refute render(view) =~ "Storage offline"

      broadcast_dir_state("/mnt/videos", :unavailable)
      html = render_after_broadcasts(view)

      assert html =~ "Storage offline"
      assert html =~ "/mnt/videos is offline"
    end

    test "shown with plural message when multiple dirs go offline", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/library")

      broadcast_dir_state("/mnt/a", :unavailable)
      broadcast_dir_state("/mnt/b", :unavailable)

      html = render_after_broadcasts(view)
      assert html =~ "2 storage locations offline"
    end

    test "clears when the dir returns to :watching", %{conn: conn} do
      broadcast_dir_state("/mnt/videos", :unavailable)
      {:ok, view, _} = live(conn, ~p"/library")
      assert render(view) =~ "Storage offline"

      broadcast_dir_state("/mnt/videos", :watching)
      html = render_after_broadcasts(view)

      refute html =~ "Storage offline"
    end
  end

  describe "Availability cache updates via watcher PubSub" do
    test "dir_state_changed updates the persistent_term cache" do
      assert Availability.dir_status() == %{}

      broadcast_dir_state("/mnt/test-dir", :unavailable)

      assert Availability.dir_status()["/mnt/test-dir"] == :unavailable
    end

    test "rebroadcasts availability_changed to subscribers" do
      :ok = Availability.subscribe()

      broadcast_dir_state("/mnt/test-dir-2", :watching)

      assert_receive {:availability_changed, "/mnt/test-dir-2", :watching}, 500
    end
  end
end
