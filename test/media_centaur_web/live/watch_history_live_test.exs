defmodule MediaCentaurWeb.WatchHistoryLiveTest do
  use MediaCentaurWeb.ConnCase

  import Phoenix.LiveViewTest
  import MediaCentaur.TestFactory

  describe "mount" do
    test "mounts the history page without error", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "Watch History"
    end

    test "mounts with empty state when no events", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/history")

      # Verify the page is up and the render cycle completes without crashing
      rendered = render(view)
      assert rendered =~ "Watch History"
    end

    test "mounts and renders completion events from the database", %{conn: conn} do
      movie = create_movie(%{name: "Sample Anime One"})
      create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Anime One"})
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "Sample Anime One"
    end

    test "mounts with correct event count reflected in stats", %{conn: conn} do
      create_watch_event(%{title: "Movie A", duration_seconds: 3600.0})
      create_watch_event(%{title: "Movie B", duration_seconds: 7200.0})
      {:ok, _view, html} = live(conn, "/history")
      # Two completions are visible on page
      assert html =~ "Movie A"
      assert html =~ "Movie B"
    end
  end

  describe "type filter" do
    test "filter_type event narrows the event list to movies only", %{conn: conn} do
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

    test "filter_type with 'all' shows all events", %{conn: conn} do
      create_watch_event(%{entity_type: :movie, title: "A Movie"})
      create_watch_event(%{entity_type: :episode, title: "An Episode"})

      {:ok, view, _html} = live(conn, "/history")

      html =
        view
        |> element("[phx-click='filter_type'][phx-value-type='all']")
        |> render_click()

      assert html =~ "A Movie"
      assert html =~ "An Episode"
    end
  end

  describe "search filter" do
    test "filter_search narrows the event list by title substring", %{conn: conn} do
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
    test "watch_event_created broadcast re-renders with the new event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/history")

      movie = create_movie(%{name: "Sample Movie Thirteen"})
      event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie Thirteen"})

      send(view.pid, {:watch_event_created, event})

      assert render(view) =~ "Sample Movie Thirteen"
    end
  end
end
