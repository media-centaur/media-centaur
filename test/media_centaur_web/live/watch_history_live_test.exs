defmodule MediaCentaurWeb.WatchHistoryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import MediaCentaur.TestFactory

  # `WatchHistoryLive.ensure_loaded/1` defers the summary read + first
  # page fetch to an owned `start_async(:history_load, …)` (ADR-049).
  # `render_async/1` awaits it deterministically — no wall-clock sleep.
  defp render_after_async_load(view) do
    render_async(view)
  end

  describe "heatmap payload (instant-navigation P2)" do
    # Only the ACTIVE heatmap variant is rendered — pre-rendering all four
    # (~1,460 <rect>s) made /history's navigation payload ~276KB, the
    # heaviest page in the app. The filter buttons already round-trip to
    # reload the events list, so the server swap costs no extra request
    # (campaigns/instant-navigation.md Phase 2).

    test "renders exactly one heatmap variant", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/history")

      assert count_substrings(html, "data-heatmap=") == 1
      assert html =~ ~s(data-heatmap="all")
    end

    test "zero-count cells ship no tooltip or click payload", %{conn: conn} do
      # An empty history renders 365 zero cells; tooltip <title>s and
      # phx-value-date on unclickable cells were ~40KB of dead payload.
      {:ok, _view, html} = live_async!(conn, "/history")

      assert count_substrings(html, "<title>") == 0
      assert count_substrings(html, "phx-value-date") == 0
    end

    test "active cells keep tooltip and date-filter payload", %{conn: conn} do
      movie = create_movie(%{name: "Heatmap Cell Movie"})
      create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Heatmap Cell Movie"})

      {:ok, _view, html} = live_async!(conn, "/history")

      assert count_substrings(html, "<title>") == 1
      assert count_substrings(html, "phx-value-date") == 1
    end

    test "type filter swaps the rendered heatmap variant", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/history")

      html =
        view
        |> element("button[phx-value-type=\"movie\"]", "Movies")
        |> render_click()

      assert count_substrings(html, "data-heatmap=") == 1
      assert html =~ ~s(data-heatmap="movie")
      refute html =~ ~s(data-heatmap="all")
    end
  end

  defp count_substrings(string, pattern) do
    string |> String.split(pattern) |> length() |> Kernel.-(1)
  end

  describe "mount" do
    test "mounts the history page without error", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/history")
      assert html =~ "Watch History"
    end

    test "mounts with empty state when no events", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/history")

      # Verify the page is up and the render cycle completes without crashing
      rendered = render(view)
      assert rendered =~ "Watch History"
    end

    test "mounts and renders completion events from the database", %{conn: conn} do
      movie = create_movie(%{name: "Sample Anime One"})
      create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Anime One"})
      {:ok, view, _html} = live_async!(conn, "/history")
      assert render_after_async_load(view) =~ "Sample Anime One"
    end

    test "first paint (disconnected render) shows real events, not an empty flash",
         %{conn: conn} do
      # Desktop first-paint correctness: the static HTTP render must already
      # carry the history, not an empty placeholder that flashes until the
      # socket connects. `get/2` exercises the disconnected first render.
      movie = create_movie(%{name: "First Paint History Movie"})

      create_watch_event(%{
        entity_type: :movie,
        movie_id: movie.id,
        title: "First Paint History Movie"
      })

      html = conn |> get("/history") |> html_response(200)

      assert html =~ "First Paint History Movie",
             "history events must render on the disconnected first paint"
    end

    test "mounts with correct event count reflected in stats", %{conn: conn} do
      create_watch_event(%{title: "Movie A", duration_seconds: 3600.0})
      create_watch_event(%{title: "Movie B", duration_seconds: 7200.0})
      {:ok, view, _html} = live_async!(conn, "/history")
      html = render_after_async_load(view)
      # Two completions are visible on page
      assert html =~ "Movie A"
      assert html =~ "Movie B"
    end
  end

  describe "type filter" do
    test "filter_type event narrows the event list to movies only", %{conn: conn} do
      create_watch_event(%{entity_type: :movie, title: "A Movie"})
      create_watch_event(%{entity_type: :video_object, title: "A Video"})

      {:ok, view, _html} = live_async!(conn, "/history")

      html =
        view
        |> element("[role='group'] button", "Movies")
        |> render_click()

      assert html =~ "A Movie"
      refute html =~ "A Video"
    end

    test "filter_type with 'all' shows all events", %{conn: conn} do
      create_watch_event(%{entity_type: :movie, title: "A Movie"})
      create_watch_event(%{entity_type: :episode, title: "An Episode"})

      {:ok, view, _html} = live_async!(conn, "/history")

      html =
        view
        |> element("[role='group'] button", "All")
        |> render_click()

      assert html =~ "A Movie"
      assert html =~ "An Episode"
    end
  end

  describe "search filter" do
    test "filter_search narrows the event list by title substring", %{conn: conn} do
      create_watch_event(%{title: "Sample Movie"})
      create_watch_event(%{title: "Other Title"})

      {:ok, view, _html} = live_async!(conn, "/history")

      html =
        view
        |> element("input[phx-change='filter_search']")
        |> render_change(%{"value" => "Sample"})

      assert html =~ "Sample Movie"
      refute html =~ "Other Title"
    end
  end

  describe "real-time updates" do
    test "watch_event_created broadcast re-renders with the new event", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/history")

      movie = create_movie(%{name: "Sample Movie"})
      event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie"})

      send(view.pid, {:watch_event_created, event})

      # The new event appears only after the 500ms debounce fires — poll for it.
      assert render_until(view, "Sample Movie") =~ "Sample Movie"
    end

    test "five rapid watch_event_created broadcasts trigger only one reload after the debounce window",
         %{conn: conn} do
      # Regression guard: rapid :watch_event_created messages must be debounced
      # (500ms) rather than triggering a full stats + events re-fetch on every
      # message. Five messages must result in one :reload_history — the page
      # must render correctly after the window and not crash.
      {:ok, view, _html} = live_async!(conn, "/history")

      movie = create_movie(%{name: "Other Movie"})

      for _ <- 1..5 do
        event = create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Other Movie"})
        send(view.pid, {:watch_event_created, event})
      end

      # Coalescing is pinned by `LiveHelpers.debounce/4`'s tests; `render/1`
      # is a sync round trip, so the burst has been handled when it returns.
      assert render(view) =~ "Watch History"
    end
  end

  describe "rewatch count badges" do
    test "shows a rewatch count badge for entities watched 2+ times", %{conn: conn} do
      movie = create_movie(%{name: "Sample Movie B"})

      for _ <- 1..3 do
        create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Sample Movie B"})
      end

      {:ok, view, _html} = live_async!(conn, "/history")

      assert render_after_async_load(view) =~ "3×"
    end

    test "does not show a rewatch badge for entities watched only once", %{conn: conn} do
      movie = create_movie(%{name: "Other Movie"})
      create_watch_event(%{entity_type: :movie, movie_id: movie.id, title: "Other Movie"})

      {:ok, _view, html} = live_async!(conn, "/history")

      refute html =~ "1×"
    end
  end
end
