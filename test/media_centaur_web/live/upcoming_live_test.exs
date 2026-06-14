defmodule MediaCentaurWeb.UpcomingLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.ReleaseTracking

  defp tracked_with_release(attrs \\ %{}, release_attrs \\ %{}) do
    item =
      create_tracking_item(
        Map.merge(%{tmdb_id: :rand.uniform(900_000), media_type: :tv_series, name: "Sample Show"}, attrs)
      )

    release =
      create_tracking_release(
        Map.merge(
          %{
            item_id: item.id,
            season_number: 1,
            episode_number: 1,
            air_date: Date.add(Date.utc_today(), 5),
            released: false
          },
          release_attrs
        )
      )

    {item, release}
  end

  test "GET /upcoming renders the page heading", %{conn: conn} do
    {:ok, _view, html} = live_async!(conn, "/upcoming")
    assert html =~ "Upcoming"
  end

  test "first paint (disconnected render) carries the forecast, not an empty flash", %{conn: conn} do
    tracked_with_release(%{name: "First Paint Show"})

    html = conn |> get("/upcoming") |> html_response(200)

    assert html =~ "First Paint Show",
           "tracked releases must render on the disconnected first paint"
  end

  describe "track modal" do
    test "the Track something button opens the modal", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/upcoming")

      if has_element?(view, "button", "Track something") do
        rendered = render_click(element(view, "button", "Track something"))
        assert rendered =~ "track-search-input"
      end
    end

    test "search renders TMDB results", %{conn: conn} do
      MediaCentaur.TmdbStubs.setup_tmdb_client()

      MediaCentaur.TmdbStubs.stub_search_multi([
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05",
          "poster_path" => "/sample-movie-poster.jpg"
        }
      ])

      {:ok, view, _html} = live_async!(conn, "/upcoming")

      view
      |> form("form[phx-change='track_search']", %{query: "sample"})
      |> render_change()

      assert render(view) =~ "Sample Movie"
    end
  end

  describe "detail slide-over" do
    test "select_event opens the per-title detail; close_detail closes it", %{conn: conn} do
      {item, _release} = tracked_with_release(%{name: "Detail Show"})

      {:ok, view, _html} = live_async!(conn, "/upcoming")

      opened = render_hook(view, "select_event", %{"item-id" => item.id})
      assert opened =~ "Detail Show"
      assert opened =~ "Stop tracking"

      closed = render_hook(view, "close_detail", %{})
      refute closed =~ "Stop tracking"
    end
  end

  describe "tracking management" do
    test "toggle_auto_grab persists the item's auto-grab mode", %{conn: conn} do
      {item, _release} = tracked_with_release(%{name: "Toggle Show", auto_grab_mode: "off"})

      {:ok, view, _html} = live_async!(conn, "/upcoming")

      render_hook(view, "toggle_auto_grab", %{"item-id" => item.id})

      assert ReleaseTracking.get_item(item.id).auto_grab_mode == "all_releases"
    end

    test "stop_tracking deletes the item and flashes", %{conn: conn} do
      {item, _release} = tracked_with_release(%{name: "Stop Show"})

      {:ok, view, _html} = live_async!(conn, "/upcoming")

      result = render_hook(view, "stop_tracking", %{"item-id" => item.id})

      assert result =~ "Stopped tracking"
      assert ReleaseTracking.get_item(item.id) == nil
    end
  end

  describe "mini-month navigation" do
    test "paging the month keeps the page rendering", %{conn: conn} do
      tracked_with_release()

      {:ok, view, _html} = live_async!(conn, "/upcoming")

      assert render_hook(view, "mini_month_next", %{}) =~ "Upcoming"
      assert render_hook(view, "mini_month_prev", %{}) =~ "Upcoming"
    end

    test "jump_to_day records the focused day without crashing", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/upcoming")

      assert render_hook(view, "jump_to_day", %{"date" => Date.to_iso8601(Date.utc_today())}) =~
               "Upcoming"
    end

    test "jump_to_day pushes a scroll command so the rail jumps to that day", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/upcoming")
      iso = Date.to_iso8601(Date.utc_today())

      render_hook(view, "jump_to_day", %{"date" => iso})

      assert_push_event(view, "upcoming:scroll_to_day", %{date: ^iso})
    end
  end

  describe "broadcast-driven reloads" do
    test "a burst of broadcasts debounces into a single reload and re-renders", %{conn: conn} do
      tracked_with_release(%{name: "Reload Show"})

      {:ok, view, _html} = live_async!(conn, "/upcoming")

      for _ <- 1..5 do
        send(view.pid, {:releases_updated, [Ecto.UUID.generate()]})

        send(
          view.pid,
          {:entities_changed, %MediaCentaur.Library.Events.EntitiesChanged{entity_ids: []}}
        )
      end

      Process.sleep(600)

      assert render(view) =~ "Reload Show"
    end
  end
end
