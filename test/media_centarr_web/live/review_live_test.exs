defmodule MediaCentarrWeb.ReviewLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  describe "GET /review" do
    test "renders without crashing", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/review")
      # Empty-state copy or list section heading.
      assert html =~ "Review" or html =~ "Movies" or html =~ "TV Series"
    end

    test "lists pending files on initial mount", %{conn: conn} do
      _file =
        create_pending_file(%{
          parsed_title: "Initial Mount Pending",
          parsed_type: "movie"
        })

      {:ok, _view, html} = live(conn, "/review")
      assert html =~ "Initial Mount Pending"
    end
  end

  describe "live updates from review intake" do
    # The review queue is the user's choke point — every file the
    # auto-matcher couldn't decide on lands here. If the LV doesn't react
    # to file_added in real time, an operator trying to clear a backlog
    # has to refresh constantly to know if new work has landed.

    test "file_added broadcast triggers a debounced reload",
         %{conn: conn} do
      {:ok, view, html} = live(conn, "/review")
      refute html =~ "Newly Arrived File"

      _file =
        create_pending_file(%{
          parsed_title: "Newly Arrived File",
          parsed_type: "movie"
        })

      send(view.pid, {:file_added, Ecto.UUID.generate()})

      # 500ms reload_groups debounce.
      Process.sleep(600)

      assert render(view) =~ "Newly Arrived File"
    end

    test "file_reviewed broadcast removes the file from the list",
         %{conn: conn} do
      file =
        create_pending_file(%{
          parsed_title: "Single Review File",
          parsed_type: "movie"
        })

      {:ok, view, html} = live(conn, "/review")
      assert html =~ "Single Review File"

      send(view.pid, {:file_reviewed, file.id})

      refute render(view) =~ "Single Review File"
    end

    test "group_approved broadcast removes the whole group from the list",
         %{conn: conn} do
      file_a =
        create_pending_file(%{
          file_path: "/media/test/Approved Show/S01E01.mkv",
          watch_directory: "/media/test",
          parsed_title: "Approved Show",
          parsed_type: "tv"
        })

      _file_b =
        create_pending_file(%{
          file_path: "/media/test/Approved Show/S01E02.mkv",
          watch_directory: "/media/test",
          parsed_title: "Approved Show",
          parsed_type: "tv"
        })

      {:ok, view, html} = live(conn, "/review")
      assert html =~ "Approved Show"

      group_key = {file_a.watch_directory, "Approved Show"}
      send(view.pid, {:group_approved, group_key, 2})

      refute render(view) =~ "Approved Show"
    end

    test "group_error broadcast surfaces a flash without removing the group",
         %{conn: conn} do
      file =
        create_pending_file(%{
          parsed_title: "Errored Group File",
          parsed_type: "movie"
        })

      {:ok, view, _html} = live(conn, "/review")

      group_key = {file.watch_directory, "Errored Group File"}
      send(view.pid, {:group_error, group_key, "boom"})

      html = render(view)
      assert html =~ "boom"
      # Group remains visible — error did not remove it from the list.
      assert html =~ "Errored Group File"
    end
  end
end
