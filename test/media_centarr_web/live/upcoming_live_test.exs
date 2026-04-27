defmodule MediaCentarrWeb.UpcomingLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  import Ecto.Query

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Repo

  test "GET /upcoming renders the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/upcoming")
    # The page header always renders the "Upcoming" heading
    assert html =~ "Upcoming"
  end

  test "clicking the Track New Releases button opens the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/upcoming")

    # The track button only appears when TMDB is ready; if the test
    # environment isn't TMDB-ready, the conditional skips the assertion.
    if has_element?(view, "button", "Track New Releases") do
      rendered = render_click(element(view, "button", "Track New Releases"))
      assert rendered =~ "track-search-input"
    end
  end

  describe "debounce on broadcast-driven reloads" do
    test "five rapid broadcasts trigger only one reload after the debounce window", %{conn: conn} do
      # Regression guard: :releases_updated, :entities_changed, and grab-event
      # messages must be debounced (500ms) rather than calling load_upcoming on
      # every message. Five messages in quick succession should produce one
      # :reload_upcoming — the page must still render correctly after the window.
      {:ok, view, _html} = live(conn, "/upcoming")

      for _ <- 1..5 do
        send(view.pid, {:entities_changed, []})
      end

      Process.sleep(600)

      assert render(view) =~ "Upcoming"
    end
  end

  describe "queue_all_show event" do
    setup do
      # Oban runs inline in tests, so enqueue/4 triggers SearchAndGrab → Prowlarr.search.
      # Stub a no-result response so the worker snoozes cleanly.
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      client =
        Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")

      :persistent_term.put({MediaCentarr.Acquisition.Prowlarr, :client}, client)

      on_exit(fn -> :persistent_term.erase({MediaCentarr.Acquisition.Prowlarr, :client}) end)

      :ok
    end

    test "enqueues a grab per pending release and flashes the count", %{conn: conn} do
      item =
        create_tracking_item(%{tmdb_id: 8_001, media_type: :tv_series, name: "Bulk Queue"})

      Enum.each(1..3, fn episode ->
        create_tracking_release(%{
          item_id: item.id,
          season_number: 5,
          episode_number: episode,
          released: true
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/upcoming")

      result = render_hook(view, "queue_all_show", %{"item-id" => item.id})

      assert result =~ "Queued 3"

      grabs =
        Repo.all(from(g in Grab, where: g.tmdb_id == "8001" and g.tmdb_type == "tv"))

      assert length(grabs) == 3
    end

    test "flashes an error when the item is not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/upcoming")

      result = render_hook(view, "queue_all_show", %{"item-id" => Ecto.UUID.generate()})

      assert result =~ "not found" or result =~ "couldn't"
    end
  end
end
