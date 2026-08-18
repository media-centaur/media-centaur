defmodule MediaCentaurWeb.WatchlistLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Discovery
  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
  end

  test "empty watchlist renders the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/watchlist")
    assert has_element?(view, "#watchlist-empty")
  end

  test "renders rows with the honest action per state", %{conn: conn} do
    {:ok, _} =
      Discovery.add_to_watchlist(%{
        tmdb_id: 777,
        media_type: :movie,
        name: "Sample Movie",
        release_date: ~D[2020-01-01]
      })

    {:ok, _} =
      Discovery.add_to_watchlist(%{
        tmdb_id: 42,
        media_type: :tv_series,
        name: "Sample Show",
        release_date: ~D[2999-01-01]
      })

    # A presentable movie (container + linked file) owning TMDB id 777.
    movie = create_standalone_movie(%{name: "Sample Movie"})
    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
    create_linked_file(%{movie_id: movie.id})

    {:ok, _view, html} = live(conn, "/watchlist")
    assert html =~ "In library"
    assert html =~ "Track release"
    await_supervised_tasks()
  end

  test "remove deletes the item live", %{conn: conn} do
    {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
    {:ok, view, _html} = live(conn, "/watchlist")

    view
    |> element("#watchlist-item-movie-777 button", "Remove")
    |> render_click()

    refute has_element?(view, "#watchlist-item-movie-777")
    refute Discovery.on_watchlist?(777, :movie)
    await_supervised_tasks()
  end

  test "watchlist events refresh the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/watchlist")
    {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
    assert render(view) =~ "Sample Movie"
    await_supervised_tasks()
  end

  test "library changes flip a row to In library without a reload", %{conn: conn} do
    {:ok, _} = Discovery.add_to_watchlist(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
    {:ok, view, html} = live(conn, "/watchlist")
    refute html =~ "In library"

    movie = create_standalone_movie(%{name: "Sample Movie"})
    create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
    create_linked_file(%{movie_id: movie.id})
    Library.broadcast_entities_changed([movie.id])

    render_until(view, "In library")
    await_supervised_tasks()
  end

  test "track action hands off to release tracking", %{conn: conn} do
    {:ok, _} =
      Discovery.add_to_watchlist(%{
        tmdb_id: 42,
        media_type: :tv_series,
        name: "Sample Show",
        release_date: ~D[2999-01-01]
      })

    {:ok, view, _html} = live(conn, "/watchlist")

    view
    |> element("#watchlist-item-tv_series-42 button", "Track release")
    |> render_click()

    assert render(view) =~ "Tracking Sample Show"

    # The tracking itself runs on a supervised context task; await it,
    # then assert the effect landed.
    await_supervised_tasks()
    assert %{tmdb_id: 42} = ReleaseTracking.get_item_by_tmdb(42, :tv_series)
  end
end
