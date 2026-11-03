defmodule MediaCentaurWeb.WatchlistLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Features
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.Watchlist
  alias MediaCentaurWeb.TitleRef

  @show {246_810, :tv_series}
  @movie {777, :movie}

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

  defp row(ref), do: "#watchlist-row-#{TitleRef.param(ref)}"
  defp rung_trigger(ref), do: "#watchlist-row-#{TitleRef.param(ref)}-rung"
  defp rung_item(ref, choice), do: "#watchlist-row-#{TitleRef.param(ref)}-rung-#{choice}"

  # A followed series with two aired episodes outstanding and one dated ahead.
  defp follow_show(name \\ "Sample Show") do
    item = create_tracking_item(%{tmdb_id: 246_810, media_type: :tv_series, name: name, rung: :follow})

    for {episode, days} <- [{1, -10}, {2, -3}, {3, 7}] do
      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: episode,
        air_date: Date.add(Date.utc_today(), days)
      })
    end

    item
  end

  # A listed movie whose digital release passed.
  defp list_movie(name \\ "Sample Movie") do
    digital = Date.utc_today() |> Date.add(-18) |> Date.to_iso8601()

    payload =
      TmdbStubs.movie_detail(%{
        "id" => 777,
        "title" => name,
        "release_date" => digital,
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" => [%{"type" => 4, "release_date" => "#{digital}T00:00:00.000Z"}]
            }
          ]
        }
      })

    create_title_intent(%{tmdb_id: 777, media_type: :movie, name: name, rung: :list, payload: payload})
  end

  describe "the inventory" do
    test "every record once, grouped by rung in page order, with its state", %{conn: conn} do
      follow_show()
      list_movie()
      create_title_intent(%{tmdb_id: 778, media_type: :movie, name: "Dismissed Movie", rung: :ignored})

      {:ok, view, html} = live_async!(conn, "/watchlist")

      assert has_element?(view, "#sidebar-watchlist[aria-current='page']")
      assert has_element?(view, "#watchlist-group-follow h2", "Tracking")
      assert has_element?(view, "#watchlist-group-list h2", "On your list")
      assert has_element?(view, "#watchlist-group-ignored h2", "Ignored")
      refute has_element?(view, "#watchlist-group-grab")

      # Page order: Tracking above On your list above Ignored.
      [follow_at, list_at, ignored_at] =
        for id <- ["watchlist-group-follow", "watchlist-group-list", "watchlist-group-ignored"] do
          {at, _length} = :binary.match(html, ~s(id="#{id}"))
          at
        end

      assert follow_at < list_at and list_at < ignored_at

      assert has_element?(
               view,
               "#{row(@show)}[data-state='episodes_out'] [data-role='state']",
               "2 episodes out"
             )

      assert has_element?(view, "#{row(@movie)}[data-state='out_now'] [data-role='state']", "Out now")

      assert has_element?(
               view,
               "#{row({778, :movie})} [data-role='state']",
               "Hidden from the Feed and Discovery"
             )

      assert html =~ "3 titles"
    end

    test "an owned title is on the list, marked, and its menu offers no Ignore", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Owned Movie"})
      create_external_id(%{source: "tmdb", external_id: "779", movie_id: movie.id})
      create_linked_file(%{movie_id: movie.id})
      create_title_intent(%{tmdb_id: 779, media_type: :movie, name: "Owned Movie", rung: :grab})

      {:ok, view, _html} = live_async!(conn, "/watchlist")
      ref = {779, :movie}

      assert has_element?(view, "#{row(ref)}[data-owned='true']", "In library")
      view |> element(rung_trigger(ref)) |> render_click()
      assert has_element?(view, rung_item(ref, "off"), "Remove")
      refute has_element?(view, rung_item(ref, "ignored"))
    end
  end

  describe "managing in place" do
    test "the rung menu moves the rung and the row regroups at once", %{conn: conn} do
      list_movie()
      {:ok, view, _html} = live_async!(conn, "/watchlist")

      refute has_element?(view, "#{rung_trigger(@movie)}-menu")
      view |> element(rung_trigger(@movie)) |> render_click()
      assert has_element?(view, "#{rung_trigger(@movie)}-menu")
      assert has_element?(view, "#{rung_item(@movie, "list")}[aria-checked='true']", "On your list")

      view |> element(rung_item(@movie, "grab")) |> render_click()

      assert Watchlist.rung(777, :movie) == :grab
      assert has_element?(view, "#watchlist-group-grab #{row(@movie)}")
      refute has_element?(view, "#watchlist-group-list")
      refute has_element?(view, "#{rung_trigger(@movie)}-menu")
      await_supervised_tasks()
    end

    test "Remove forgets the record; Ignore moves it to the Ignored group; Stop ignoring forgets it",
         %{conn: conn} do
      list_movie()
      follow_show()
      {:ok, view, _html} = live_async!(conn, "/watchlist")

      view |> element(rung_trigger(@movie)) |> render_click()
      view |> element(rung_item(@movie, "ignored")) |> render_click()
      assert Watchlist.rung(777, :movie) == :ignored
      assert has_element?(view, "#watchlist-group-ignored #{row(@movie)}")

      view |> element(rung_trigger(@movie)) |> render_click()
      assert has_element?(view, rung_item(@movie, "off"), "Stop ignoring")
      view |> element(rung_item(@movie, "off")) |> render_click()
      assert Watchlist.rung(777, :movie) == nil
      refute has_element?(view, row(@movie))

      view |> element(rung_trigger(@show)) |> render_click()
      view |> element(rung_item(@show, "off")) |> render_click()
      assert Watchlist.rung(246_810, :tv_series) == nil
      assert has_element?(view, "#watchlist-empty", "Your list starts with a bookmark")
      await_supervised_tasks()
    end

    test "a row opens the title detail on this page", %{conn: conn} do
      list_movie()
      {:ok, view, _html} = live_async!(conn, "/watchlist")

      view |> element(row(@movie)) |> render_click()
      assert_patch(view, "/watchlist?title=#{TitleRef.param(@movie)}")
      assert render(view) =~ "Sample Movie"
    end

    test "a rung moved elsewhere re-reads the rows", %{conn: conn} do
      list_movie()
      {:ok, view, _html} = live_async!(conn, "/watchlist")
      refute has_element?(view, "#watchlist-group-grab")

      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})
      {:ok, _intent} = Watchlist.put_rung(title, :grab)

      render_until(view, fn html -> html =~ ~s(id="watchlist-group-grab") end, 2_000)
      await_supervised_tasks()
    end
  end

  describe "narrowing" do
    test "the type filter and the search; nothing matching says so with Show all", %{conn: conn} do
      follow_show()
      list_movie()
      {:ok, view, _html} = live_async!(conn, "/watchlist")

      view |> element("#watchlist-filter [phx-value-choice='movies']") |> render_click()
      assert has_element?(view, row(@movie))
      refute has_element?(view, row(@show))

      view |> element("#watchlist-search") |> render_change(%{"value" => "show"})
      assert has_element?(view, "#watchlist-nothing-matches", "Nothing on your list matches")

      view |> element("#watchlist-nothing-matches button", "Show all") |> render_click()
      assert has_element?(view, row(@movie))
      assert has_element?(view, row(@show))

      view |> element("#watchlist-search") |> render_change(%{"value" => "SHOW"})
      assert has_element?(view, row(@show))
      refute has_element?(view, row(@movie))
    end
  end

  describe "empty (UIDR-034)" do
    test "no record: the bookmark starts the list; the button goes to Discovery while it is on", %{
      conn: conn
    } do
      {:ok, view, html} = live_async!(conn, "/watchlist")

      assert has_element?(view, "#watchlist-empty", "Your list starts with a bookmark")
      assert has_element?(view, "#watchlist-empty a[href='/discovery']", "Open Discovery")
      refute html =~ "watchlist-filter"
    end

    test "with Discovery off the button goes to the library", %{conn: conn} do
      Features.set(:discovery, false)
      {:ok, view, _html} = live_async!(conn, "/watchlist")

      assert has_element?(view, "#watchlist-empty a[href='/library']", "Browse the library")
      refute has_element?(view, "#watchlist-empty a[href='/discovery']")
    end
  end
end
