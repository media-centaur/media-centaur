defmodule MediaCentaurWeb.LibraryLiveAvailabilityTest do
  @moduledoc """
  End-to-end coverage for the "storage unmounted → offline tiles +
  banner" chain. Drives the flow through the real PubSub channels used
  in production: `Topics.dir_state/0` → `Library.MediaFileAvailability`
  GenServer → `"library:availability"` topic → the Browse projection's
  rebuild → `{:library_view_updated, :browse}` → `LibraryLive`. The
  Cache.Worker that rebuilds the projection on the availability event
  in production is not running under ConnCase, so each broadcast here is
  followed by the rebuild it would have triggered.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Library.MediaFileAvailability
  alias MediaCentaur.Library.Views.Browse

  # Replays the watcher's broadcast format so we exercise the real
  # GenServer path without needing a drive unmount. The public
  # `__sync_for_test__/0` call guarantees the message has been
  # processed (and the re-broadcast sent) before we return; the
  # projection rebuild then announces the change to the page.
  defp broadcast_dir_state(dir, state) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.dir_state(),
      {:dir_state_changed, dir, :media_dir, state}
    )

    :ok = MediaFileAvailability.__sync_for_test__()
    :ok = Browse.refresh_cache()
  end

  # Forces a LiveView re-render and waits for any pending messages
  # in its mailbox to process. `render/1` sends a sync message through
  # the LiveView channel machinery — by the time it returns, prior
  # messages have been handled.
  defp render_after_broadcasts(view), do: render(view)

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

  describe "offline entries" do
    test "an entry on an offline directory renders the offline block, no artwork, no Play; artwork returns with the drive",
         %{conn: conn} do
      movie = create_standalone_movie(%{name: "Offline Sample"})
      _file = create_linked_file(%{movie_id: movie.id, media_dir: "/mnt/videos"})

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      broadcast_dir_state("/mnt/videos", :unavailable)
      {:ok, view, _html} = live(conn, ~p"/library")

      assert has_element?(view, "[aria-label='Artwork unavailable — storage not mounted']")
      refute has_element?(view, "img[src*='/media-images/#{movie.id}/poster.jpg']")
      refute has_element?(view, "#entity-#{movie.id} .play-overlay")

      broadcast_dir_state("/mnt/videos", :watching)
      render_after_broadcasts(view)

      refute has_element?(view, "[aria-label='Artwork unavailable — storage not mounted']")
      assert has_element?(view, "img[src*='/media-images/#{movie.id}/poster.jpg']")
      assert has_element?(view, "#entity-#{movie.id} .play-overlay")
    end
  end

  describe "MediaFileAvailability cache updates via watcher PubSub" do
    test "dir_state_changed updates the persistent_term cache" do
      assert MediaFileAvailability.dir_status() == %{}

      broadcast_dir_state("/mnt/test-dir", :unavailable)

      assert MediaFileAvailability.dir_status()["/mnt/test-dir"] == :unavailable
    end

    test "rebroadcasts availability_changed to subscribers" do
      :ok = MediaFileAvailability.subscribe()

      broadcast_dir_state("/mnt/test-dir-2", :watching)

      assert_receive {:availability_changed, "/mnt/test-dir-2", :watching}, 500
    end
  end
end
