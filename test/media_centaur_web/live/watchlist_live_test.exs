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
    item =
      create_tracking_item(%{
        tmdb_id: 246_810,
        media_type: :tv_series,
        name: name,
        rung: :follow,
        payload:
          TmdbStubs.tv_detail(%{
            "id" => 246_810,
            "name" => name,
            "number_of_seasons" => 1,
            "seasons" => [%{"season_number" => 1, "episode_count" => 3}],
            "last_episode_to_air" => %{"season_number" => 1, "episode_number" => 2},
            "next_episode_to_air" => %{
              "season_number" => 1,
              "episode_number" => 3,
              "air_date" => Date.utc_today() |> Date.add(7) |> Date.to_iso8601()
            },
            "poster_path" => nil,
            "backdrop_path" => nil
          })
      })

    # The season the store will want on a rebuild (Caught up rebuilds the calendar).
    TmdbStubs.stub_routes([
      {"/tv/246810/season/1",
       %{
         "season_number" => 1,
         "episodes" =>
           for {episode, days} <- [{1, -10}, {2, -3}, {3, 7}] do
             %{
               "episode_number" => episode,
               "name" => "Episode #{episode}",
               "air_date" => Date.utc_today() |> Date.add(days) |> Date.to_iso8601()
             }
           end
       }}
    ])

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

      assert has_element?(view, "#sidebar [aria-label='Watchlist'][aria-current='page']")
      assert has_element?(view, "#watchlist-group-follow h2", "Tracking")
      assert has_element?(view, "#watchlist-group-list h2", "On your list")
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

      # The Ignored group is closed on every visit, its head carrying the
      # count; the page's count leaves Ignored out.
      refute has_element?(view, row({778, :movie}))
      assert has_element?(view, "#watchlist-group-ignored-head[aria-expanded='false']", "Ignored")
      assert has_element?(view, "#watchlist-group-ignored-head", "1")
      assert html =~ "2 titles"

      view |> element("#watchlist-group-ignored-head") |> render_click()

      assert has_element?(
               view,
               "#{row({778, :movie})} [data-role='state']",
               "Hidden from the Feed and Discovery"
             )

      # An Ignored row draws no poster, whatever the store holds.
      refute has_element?(view, "#{row({778, :movie})} img")
    end

    test "a search holds the Ignored group open while it is on", %{conn: conn} do
      list_movie()
      create_title_intent(%{tmdb_id: 778, media_type: :movie, name: "Dismissed Movie", rung: :ignored})
      {:ok, view, _html} = live_async!(conn, "/watchlist")
      refute has_element?(view, row({778, :movie}))

      view |> element("#watchlist-search") |> render_change(%{"value" => "dismissed"})
      assert has_element?(view, row({778, :movie}))
      refute has_element?(view, row(@movie))

      view |> element("#watchlist-search") |> render_change(%{"value" => ""})
      refute has_element?(view, row({778, :movie}))
    end

    test "an owned title is on the list, marked, and its menu offers no Ignore", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Owned Movie"})
      create_external_id(%{source: "tmdb", external_id: "779", movie_id: movie.id})
      create_linked_file(%{movie_id: movie.id})
      create_title_intent(%{tmdb_id: 779, media_type: :movie, name: "Owned Movie", rung: :grab})

      {:ok, view, _html} = live_async!(conn, "/watchlist")
      ref = {779, :movie}

      assert has_element?(view, row(ref), "In library")
      view |> element(rung_trigger(ref)) |> render_click()
      assert has_element?(view, rung_item(ref, "off"), "Remove")
      refute has_element?(view, rung_item(ref, "ignored"))
    end
  end

  describe "Between seasons and Series you've watched" do
    # A library series this profile finished an episode of, with the
    # store's record carrying TMDB's status.
    defp watched_series(tmdb_id, name, status) do
      tv = create_tv_series(%{name: name})
      create_external_id(%{tv_series_id: tv.id, source: "tmdb", external_id: Integer.to_string(tmdb_id)})
      season = create_season(%{tv_series_id: tv.id, season_number: 1})
      episode = create_episode(%{season_id: season.id, episode_number: 1, name: "Episode 1"})
      create_playable_item_for_episode(episode)
      create_watch_progress(%{episode_id: episode.id, completed: true})

      create_title_record(%{
        tmdb_id: tmdb_id,
        media_type: :tv_series,
        payload: TmdbStubs.tv_detail(%{"id" => tmdb_id, "name" => name, "status" => status})
      })
    end

    test "a watched, returning series with no record is offered in a closed group; Tracking adds it",
         %{conn: conn} do
      list_movie()
      watched_series(246_812, "Watched Show", "Returning Series")
      watched_series(246_813, "Finished Show", "Ended")
      ref = {246_812, :tv_series}

      {:ok, view, html} = live_async!(conn, "/watchlist")

      assert has_element?(
               view,
               "#watchlist-group-watched-head[aria-expanded='false']",
               "Series you've watched"
             )

      assert has_element?(view, "#watchlist-group-watched-head", "1")
      refute has_element?(view, row(ref))
      # The page's count is records only.
      assert html =~ "1 title"

      view |> element("#watchlist-group-watched-head") |> render_click()
      assert has_element?(view, row(ref), "In library")
      assert has_element?(view, rung_trigger(ref), "Not listed")
      refute has_element?(view, row({246_813, :tv_series}))

      view |> element(rung_trigger(ref)) |> render_click()
      refute has_element?(view, rung_item(ref, "off"))
      view |> element(rung_item(ref, "follow")) |> render_click()

      assert Watchlist.rung(246_812, :tv_series) == :follow
      refute has_element?(view, "#watchlist-group-watched")
    end

    test "a followed series with nothing dated that TMDB says returns sits in the closed Between seasons group",
         %{conn: conn} do
      list_movie()

      create_tracking_item(%{
        tmdb_id: 246_814,
        media_type: :tv_series,
        name: "Waiting Show",
        rung: :follow,
        payload:
          TmdbStubs.tv_detail(%{
            "id" => 246_814,
            "name" => "Waiting Show",
            "status" => "Returning Series",
            "next_episode_to_air" => nil
          })
      })

      {:ok, view, _html} = live_async!(conn, "/watchlist")

      assert has_element?(
               view,
               "#watchlist-group-between_seasons-head[aria-expanded='false']",
               "Between seasons"
             )

      refute has_element?(view, "#watchlist-group-follow")

      view |> element("#watchlist-group-between_seasons-head") |> render_click()
      assert has_element?(view, "#watchlist-group-between_seasons #{row({246_814, :tv_series})}")
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
      refute has_element?(view, row(@movie))
      view |> element("#watchlist-group-ignored-head") |> render_click()
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

    test "Caught up on a row sets the point to the latest aired episode: the row says so, nothing is out",
         %{
           conn: conn
         } do
      follow_show()
      {:ok, view, _html} = live_async!(conn, "/watchlist")
      assert has_element?(view, "#{row(@show)} [data-role='state']", "2 episodes out")

      view |> element("#{row(@show)}-caught-up", "Caught up") |> render_click()

      assert Watchlist.caught_up(246_810, :tv_series) == {1, 2}

      assert has_element?(
               view,
               "#{row(@show)}[data-state='next_episode'] [data-role='state']",
               "Caught up through S01E02"
             )

      assert has_element?(view, "#{row(@show)} [data-role='state']", "Next episode")
      refute has_element?(view, "#{row(@show)}-caught-up")
      await_supervised_tasks()
    end

    test "the detail's tracking card shows the point and moves it", %{conn: conn} do
      follow_show()
      {:ok, view, _html} = live_async!(conn, "/watchlist")
      view |> element(row(@show)) |> render_click()

      assert has_element?(view, "#detail-caught-up [data-role='season']", "—")
      view |> element("#detail-caught-up-latest", "Caught up") |> render_click()
      assert Watchlist.caught_up(246_810, :tv_series) == {1, 2}
      assert has_element?(view, "#detail-caught-up[data-point='1-2'] [data-role='episode']", "Episode 2")

      view |> element("#detail-caught-up-episode") |> render_click()
      view |> element("#detail-caught-up-episode-1") |> render_click()
      assert Watchlist.caught_up(246_810, :tv_series) == {1, 1}
      assert has_element?(view, "#detail-caught-up[data-point='1-1']")
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
      {:ok, view, _html} = live_async!(conn, "/watchlist")

      assert has_element?(view, "#watchlist-empty", "Your list starts with a bookmark")
      assert has_element?(view, "#watchlist-empty a[href='/discovery']", "Open Discovery")
      refute has_element?(view, "#watchlist-filter")
    end

    test "with Discovery off the button goes to the library", %{conn: conn} do
      Features.set(:discovery, false)
      {:ok, view, _html} = live_async!(conn, "/watchlist")

      assert has_element?(view, "#watchlist-empty a[href='/library']", "Browse the library")
      refute has_element?(view, "#watchlist-empty a", "Open Discovery")
    end
  end
end
