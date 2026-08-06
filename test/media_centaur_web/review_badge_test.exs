defmodule MediaCentaurWeb.ReviewBadgeTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Reconciliation
  alias MediaCentaur.Review.Events.FileAdded
  alias MediaCentaur.Review.Events.FileReviewed

  @sidebar_review ~s{aside a[data-tip="Review"]}

  defp divert_awaiting_file do
    {:ok, awaiting_file} =
      Reconciliation.divert(%{
        file_path: "/media/Sample Show/S02E01.mkv",
        media_dir: "/media",
        tmdb_id: 4242,
        series_title: "Sample Show",
        claimed_season: 2,
        claimed_episode: 1
      })

    awaiting_file
  end

  describe "sidebar Review entry" do
    test "is hidden when nothing awaits review", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")

      refute has_element?(view, @sidebar_review)
    end

    test "appears with the combined count when identity work exists", %{conn: conn} do
      create_pending_file()
      create_pending_file()

      {:ok, view, _html} = live(conn, ~p"/history")

      assert has_element?(view, @sidebar_review <> ~s{[href="/review"]})
      assert has_element?(view, @sidebar_review, "2")
      # The standalone Episode-mapping entry is gone from the sidebar.
      refute has_element?(view, ~s{aside a[data-tip="Episode mapping"]})
    end

    test "targets the mapping queue when only mapping work exists", %{conn: conn} do
      divert_awaiting_file()

      {:ok, view, _html} = live(conn, ~p"/history")

      assert has_element?(view, @sidebar_review <> ~s{[href="/reconcile"]})
      assert has_element?(view, @sidebar_review, "1")
    end

    test "stays lit while on the mapping page", %{conn: conn} do
      divert_awaiting_file()

      {:ok, view, _html} = live(conn, ~p"/reconcile")

      assert has_element?(view, @sidebar_review <> ".sidebar-link-active")
    end

    test "live-updates when review work arrives and drains", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")

      refute has_element?(view, @sidebar_review)

      pending_file = create_pending_file()
      send(view.pid, {:file_added, %FileAdded{pending_file_id: pending_file.id}})

      assert has_element?(view, @sidebar_review <> ~s{[href="/review"]})

      MediaCentaur.Review.destroy_pending_file!(pending_file)
      send(view.pid, {:file_reviewed, %FileReviewed{pending_file_id: pending_file.id}})

      refute has_element?(view, @sidebar_review)
    end

    test "live-updates on reconciliation changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")

      divert_awaiting_file()
      send(view.pid, {:reconciliation_updated})

      assert has_element?(view, @sidebar_review <> ~s{[href="/reconcile"]})
    end
  end

  describe "review tab strip" do
    test "links the two review dimensions with their counts", %{conn: conn} do
      create_pending_file()
      divert_awaiting_file()

      {:ok, review_view, _html} = live(conn, ~p"/review")

      assert has_element?(review_view, ~s{[data-nav-zone="review-tabs"] a[href="/reconcile"]}, "1")

      {:ok, reconcile_view, _html} = live(conn, ~p"/reconcile")

      assert has_element?(reconcile_view, ~s{[data-nav-zone="review-tabs"] a[href="/review"]}, "1")
    end
  end
end
