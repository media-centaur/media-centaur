defmodule MediaCentaurWeb.WatchHistoryLiveTest do
  use MediaCentaurWeb.ConnCase

  import Phoenix.LiveViewTest
  import MediaCentaur.TestFactory

  describe "mount" do
    test "renders the history page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "Watch History"
    end

    test "shows zero stats when no events", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "0"
    end

    test "shows completion events", %{conn: conn} do
      movie = create_movie(%{name: "Sample Anime One"})
      create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Anime One"})
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "Sample Anime One"
    end

    test "shows stat totals", %{conn: conn} do
      create_watch_event(%{title: "Movie A", duration_seconds: 3600.0})
      create_watch_event(%{title: "Movie B", duration_seconds: 7200.0})
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "2"
    end
  end

  describe "type filter" do
    test "filter_type event narrows the list", %{conn: conn} do
      create_watch_event(%{entity_type: :movie, title: "A Movie"})
      create_watch_event(%{entity_type: :video_object, title: "A Video"})

      {:ok, view, _html} = live(conn, "/history")

      html =
        view
        |> element("[phx-click='filter_type'][phx-value-type='movie']")
        |> render_click()

      assert html =~ "A Movie"
      refute html =~ "A Video"
    end
  end

  describe "search filter" do
    test "filter_search narrows the list by title", %{conn: conn} do
      create_watch_event(%{title: "Sample Movie"})
      create_watch_event(%{title: "Alien"})

      {:ok, view, _html} = live(conn, "/history")

      html =
        view
        |> element("input[phx-change='filter_search']")
        |> render_change(%{"value" => "Blade"})

      assert html =~ "Sample Movie"
      refute html =~ "Alien"
    end
  end

  describe "real-time updates" do
    test "a new watch_event_created broadcast adds the event to the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/history")
      assert render(view) =~ "0"

      movie = create_movie(%{name: "Sample Movie Thirteen"})
      event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Thirteen"})

      send(view.pid, {:watch_event_created, event})
      assert render(view) =~ "Sample Movie Thirteen"
    end
  end
end
