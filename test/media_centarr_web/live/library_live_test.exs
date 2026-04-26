defmodule MediaCentarrWeb.LibraryLiveTest do
  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  import Ecto.Query

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Repo
  alias MediaCentarr.Watcher.FilePresence

  describe "skeleton" do
    test "renders zone tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Continue Watching"
      assert html =~ "Library"
    end
  end

  describe "detail modal dismissal" do
    # Regression: clicking inside a sibling overlay (e.g. Console drawer)
    # must not dismiss the detail modal. The dismiss mechanism must
    # therefore be backdrop-scoped, not document-scoped (no phx-click-away
    # on the panel). These tests pin that wiring.

    setup do
      movie = create_standalone_movie(%{name: "Dismiss Fixture"})
      file = create_linked_file(%{movie_id: movie.id})
      FilePresence.record_file(file.file_path, file.watch_dir)
      {:ok, movie: movie}
    end

    test "clicking the backdrop closes the modal", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live(conn, ~p"/?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")

      view |> element("#detail-modal") |> render_click()

      refute has_element?(view, "#detail-modal[data-state='open']")
    end

    test "the modal panel has no document-scoped dismiss handler", %{
      conn: conn,
      movie: movie
    } do
      # Structural invariant: nothing inside the detail modal may use
      # phx-click-away. That handler is document-scoped, so any sibling
      # overlay (Console drawer, future popover, toast) would dismiss
      # the modal when clicked. Dismissal lives on the backdrop instead.
      {:ok, view, _html} = live(conn, ~p"/?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")
      refute has_element?(view, "#detail-modal [phx-click-away]")
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

      {:ok, view, _html} = live(conn, ~p"/?zone=upcoming")

      result = render_hook(view, "queue_all_show", %{"item-id" => item.id})

      assert result =~ "Queued 3"

      grabs =
        Repo.all(from(g in Grab, where: g.tmdb_id == "8001" and g.tmdb_type == "tv"))

      assert length(grabs) == 3
    end

    test "flashes an error when the item is not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?zone=upcoming")

      result = render_hook(view, "queue_all_show", %{"item-id" => Ecto.UUID.generate()})

      assert result =~ "not found" or result =~ "couldn't"
    end
  end
end
