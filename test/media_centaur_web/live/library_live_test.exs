defmodule MediaCentaurWeb.LibraryLiveTest do
  use MediaCentaurWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "skeleton" do
    test "renders zone tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Continue Watching"
      assert html =~ "Library"
    end
  end

  describe "watch history widget" do
    test "mounts and shows the history widget", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "watch-history-widget"
      assert html =~ "Watch History"
    end

    test "real-time update: receiving watch_event_created refreshes stats", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      event = %MediaCentaur.WatchHistory.Event{
        id: Ecto.UUID.generate(),
        title: "Test Movie",
        entity_type: :movie,
        duration_seconds: 7200.0,
        completed_at: DateTime.utc_now(),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      send(view.pid, {:watch_event_created, event})

      # The socket should handle the message without crashing
      assert render(view) =~ "watch-history-widget"
    end
  end
end
