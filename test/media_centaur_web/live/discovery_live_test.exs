defmodule MediaCentaurWeb.DiscoveryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Translation
  alias MediaCentaur.Features
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.NewReleases
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Secret
  alias MediaCentaur.Social
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.Watchlist

  describe "the feature (ADR-081)" do
    test "on by default: the sidebar entry and the page", %{conn: conn} do
      TmdbStubs.mark_ready!()
      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, "[data-tip='Discovery']")
      refute has_element?(view, "#discovery-off")
      assert has_element?(view, "#omnibox-media-input")
    end

    test "off: no sidebar entry, and the page is its off state with Turn on",
         %{conn: conn} do
      Features.set(:discovery, false)

      {:ok, view, _html} = live(conn, "/discovery")
      refute has_element?(view, "[data-tip='Discovery']")
      assert has_element?(view, "#discovery-off")
      assert render(view) =~ "Discovery is off"

      view |> element("#discovery-off-turn-on") |> render_click()
      assert Features.enabled?(:discovery)
    end

    test "the Feature flags row lists it as optional, on", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/settings?section=features")
      assert html =~ "Discovery"
      refute html =~ "In development."
    end
  end

  describe "the New Releases shelf" do
    setup do
      TmdbStubs.mark_ready!()
      :ok
    end

    defp store_movie(tmdb_id, name) do
      create_title_record(%{
        tmdb_id: tmdb_id,
        media_type: :movie,
        payload:
          TmdbStubs.movie_detail(%{"id" => tmdb_id, "title" => name, "release_date" => "2026-10-02"})
      })
    end

    defp digital(tmdb_id), do: %{tmdb_id: tmdb_id, digital_date: ~D[2026-10-30]}

    test "the membership in shelf order, from the store's records; a tile opens the title detail",
         %{conn: conn} do
      store_movie(901, "Movie A")
      store_movie(902, "Movie B")
      :ok = NewReleases.replace([digital(902), digital(901)])

      {:ok, view, html} = live(conn, "/discovery")

      assert has_element?(view, "#new-releases-row-movie-902")
      assert has_element?(view, "#new-releases-row-movie-901")
      assert :binary.match(html, "Movie B") < :binary.match(html, "Movie A")
      refute has_element?(view, "#discovery-empty")

      view |> element("#new-releases-row-movie-901") |> render_click()
      assert_patch(view, "/discovery?title=movie-901")
    end

    test "a member without a record is not drawn, an ignored one is dropped, an owned one says In library",
         %{conn: conn} do
      store_movie(901, "Movie A")
      store_movie(902, "Movie B")
      store_movie(903, "Movie C")
      create_title_intent(%{tmdb_id: 902, media_type: :movie, rung: :ignored, name: "Movie B"})
      movie = create_movie(%{name: "Movie C", tmdb_id: "903"})
      _ = create_linked_file(%{movie_id: movie.id})
      :ok = NewReleases.replace([digital(901), digital(902), digital(903), digital(904)])

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, "#new-releases-row-movie-901")
      refute has_element?(view, "#new-releases-row-movie-902")
      refute has_element?(view, "#new-releases-row-movie-904")
      assert has_element?(view, "#new-releases-row-movie-903", "In library")
    end

    test "the tile's toolbar: the bookmark lists the title, Ignore hides it, Undo brings it back",
         %{conn: conn} = context do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.setup_artwork_cache(context)
      store_movie(901, "Movie A")
      :ok = NewReleases.replace([digital(901)])

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "#new-releases-row-movie-901-list[aria-label='Add to watchlist']")

      view |> element("#new-releases-row-movie-901-list") |> render_click()
      assert MediaCentaur.Watchlist.rung(901, :movie) == :list
      assert render_until(view, "On your list") =~ "On your list"
      assert has_element?(view, "#new-releases-row-movie-901-list[aria-label='Remove from watchlist']")

      view |> element("#new-releases-row-movie-901-ignore") |> render_click()
      assert MediaCentaur.Watchlist.rung(901, :movie) == :ignored
      assert has_element?(view, "#ignore-undo", "Movie A ignored")
      assert render_until(view, "New releases are on their way") =~ "New releases are on their way"

      view |> element("#ignore-undo-action") |> render_click()
      assert MediaCentaur.Watchlist.rung(901, :movie) == :list
      assert render_until(view, "Movie A") =~ "Movie A"
      refute has_element?(view, "#ignore-undo")
      await_supervised_tasks()
    end

    test "the hero is a member with a backdrop on disk: the canvas, the lockup or name, and its three actions",
         %{conn: conn} = context do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.setup_artwork_cache(context)
      store_movie(901, "Movie A")
      store_movie(902, "Movie B")
      backdrop = MediaCentaur.TmdbArtwork.on_disk_path(:backdrop, :movie, 902)
      File.mkdir_p!(Path.dirname(backdrop))
      File.write!(backdrop, "jpeg")
      :ok = NewReleases.replace([digital(901), digital(902)])

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(
               view,
               "canvas#hero-backdrop[phx-hook='HeroBackdrop'][data-src*='movie-902/backdrop.jpg']"
             )

      assert has_element?(view, "[data-nav-zone='hero'] [data-component='hero'] h1", "Movie B")
      assert has_element?(view, "#discovery-hero-list[aria-pressed='false']", "Add to watchlist")
      assert has_element?(view, "[data-nav-zone='hero'] button", "Download")
      refute has_element?(view, "h1", "Discovery")

      view |> element("#discovery-hero-list") |> render_click()
      assert MediaCentaur.Watchlist.rung(902, :movie) == :list
      assert render_until(view, "On your watchlist") =~ "On your watchlist"

      view |> element("#discovery-hero-more") |> render_click()
      assert_patch(view, "/discovery?title=movie-902")
      await_supervised_tasks()
    end

    test "no member with a backdrop on disk: no hero, no canvas, the page title stays", %{conn: conn} do
      store_movie(901, "Movie A")
      :ok = NewReleases.replace([digital(901)])

      {:ok, view, _html} = live(conn, "/discovery")

      refute has_element?(view, "canvas#hero-backdrop")
      refute has_element?(view, "[data-nav-zone='hero']")
      assert has_element?(view, "h1", "Discovery")
    end

    test "the shelf follows the membership", %{conn: conn} do
      store_movie(901, "Movie A")
      store_movie(902, "Movie B")
      :ok = NewReleases.replace([digital(901)])

      {:ok, view, html} = live(conn, "/discovery")
      refute html =~ "Movie B"

      :ok = NewReleases.replace([digital(901), digital(902)])
      assert render_until(view, "Movie B") =~ "Movie B"
    end

    test "nothing stored yet: the page says the first refresh is on its way", %{conn: conn} do
      {:ok, view, html} = live(conn, "/discovery")

      assert has_element?(view, "#discovery-empty")
      assert html =~ "New releases are on their way"
    end

    test "nothing stored and TMDB down: the page says the shelf fills when TMDB is back",
         %{conn: conn} do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      {:ok, _view, html} = live(conn, "/discovery")
      assert html =~ "New releases arrive when TMDB is back"
    end
  end

  describe "the watchlist shelves" do
    setup do
      TmdbStubs.mark_ready!()
      :ok
    end

    defp typed(dates) do
      %{
        "results" => [
          %{
            "iso_3166_1" => "US",
            "release_dates" =>
              Enum.map(dates, fn {type, date} ->
                %{"type" => type, "release_date" => "#{date}T00:00:00.000Z"}
              end)
          }
        ]
      }
    end

    defp list_movie(tmdb_id, name, rung, dates) do
      create_title_intent(%{
        tmdb_id: tmdb_id,
        media_type: :movie,
        name: name,
        rung: rung,
        payload:
          TmdbStubs.movie_detail(%{
            "id" => tmdb_id,
            "title" => name,
            "release_date" => nil,
            "release_dates" => typed(dates)
          })
      })
    end

    test "Out Now first, the Watchlist grouped row last with In Theaters and Coming Up chips; an owned title is on neither",
         %{conn: conn} do
      today = Date.utc_today()
      list_movie(901, "Movie Out", :follow, [{3, Date.add(today, -60)}, {4, Date.add(today, -5)}])
      list_movie(902, "Movie Opened", :list, [{3, Date.add(today, -12)}])
      list_movie(903, "Movie Ahead", :list, [{3, Date.add(today, 45)}])
      list_movie(904, "Movie Owned", :list, [{4, Date.add(today, -5)}])
      movie = create_movie(%{name: "Movie Owned", tmdb_id: "904"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, html} = live(conn, "/discovery")

      assert has_element?(view, "#out-now-row-movie-901", "Tracking")

      assert has_element?(
               view,
               "#watchlist-row [data-group='In Theaters'] #watchlist-row-movie-902",
               MediaCentaur.Format.month_day(Date.add(today, -12))
             )

      assert has_element?(view, "#watchlist-row [data-group='Coming Up'] #watchlist-row-movie-903")
      refute html =~ "Movie Owned"
      assert :binary.match(html, "Out Now") < :binary.match(html, "data-row=\"watchlist\"")
    end

    test "a followed series the library holds is on Out Now when a new season airs, its tile naming the season",
         %{conn: conn} do
      today = Date.utc_today()

      item =
        create_tracking_item(%{
          tmdb_id: 906,
          media_type: :tv_series,
          name: "Show Returning",
          rung: :follow
        })

      for {season, episode, days} <- [{1, 1, -400}, {2, 1, -3}] do
        create_tracking_release(%{
          item_id: item.id,
          season_number: season,
          episode_number: episode,
          air_date: Date.add(today, days)
        })
      end

      tv = create_tv_series(%{name: "Show Returning"})
      create_external_id(%{tv_series_id: tv.id, source: "tmdb", external_id: "906"})
      season = create_season(%{tv_series_id: tv.id, season_number: 1})
      create_episode(%{season_id: season.id, episode_number: 1, name: "Episode 1"})
      :ok = MediaCentaur.ReleaseTracking.LibraryLinks.refresh_for([tv.id])

      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, "#out-now-row-tv_series-906", "Season 2")
    end
  end

  describe "Reviewed by Friends" do
    alias MediaCentaur.Social.Identity

    @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
    @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

    setup context do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.setup_artwork_cache(context)
      Identity.ensure()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      title = Title.new!(%{tmdb_id: 905, media_type: :movie, name: "Movie Reviewed"})

      event =
        Event.sign(
          Translation.to_event(:review, title, [sentiment: :love, text: "yes"], @friend_pubkey),
          @friend_secret
        )

      {:ok, _activity} = Activities.ingest(event)
      await_supervised_tasks()
      :ok
    end

    test "a friend's review puts the title on the shelf with its glyph; the shelf links to Social", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/discovery")

      assert has_element?(view, "#friends-row-movie-905 [data-role='social-glyphs']")
      assert has_element?(view, "[data-row='friends'] a[href='/social']", "See all")
    end

    test "with Social off the shelf is gone", %{conn: conn} do
      Features.set(:social, false)

      {:ok, view, _html} = live(conn, "/discovery")
      refute has_element?(view, "#friends-row")
    end
  end

  describe "media search (UIDR-014, amended)" do
    setup do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.mark_ready!()
      :ok
    end

    test "a query owns the page: the hero and the shelves go, the results answer flat, a row opens the detail, clearing brings the page back",
         %{conn: conn} do
      create_title_record(%{
        tmdb_id: 901,
        media_type: :movie,
        payload: TmdbStubs.movie_detail(%{"id" => 901, "title" => "Movie A"})
      })

      :ok = NewReleases.replace([%{tmdb_id: 901, digital_date: ~D[2026-10-30]}])

      TmdbStubs.stub_search_multi([
        %{
          "id" => 424_242,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      assert has_element?(view, "[data-nav-zone='omnibox'] #omnibox-media-input")
      assert has_element?(view, "#new-releases-row-movie-901")

      view |> form("form[phx-change='omnibox_change']", %{query: "sample"}) |> render_change()
      render_async(view, 2_000)

      assert has_element?(view, "#omnibox-result-movie-424242", "Sample Movie")
      refute has_element?(view, "#new-releases-row-movie-901")
      refute has_element?(view, "[data-nav-zone='hero']")

      view |> element("#omnibox-result-movie-424242") |> render_click()
      assert_patch(view, "/discovery?title=movie-424242")

      render_click(view, "omnibox_clear", %{})
      assert has_element?(view, "#new-releases-row-movie-901")
      refute has_element?(view, "#omnibox-result-movie-424242")
    end

    test "without TMDB the box is not offered; the capability gap says what to do", %{conn: conn} do
      TmdbStubs.mark_unconfigured!()

      {:ok, view, html} = live(conn, "/discovery")
      refute has_element?(view, "#omnibox-media-input")
      assert html =~ "Connect TMDB to fill this page"
    end
  end

  describe "media search — the results (UIDR-014, amended; moved from Downloads at the cutover)" do
    setup do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.mark_ready!()
      :ok
    end

    defp search(view, query) do
      view |> form("form[phx-change='omnibox_change']", %{query: query}) |> render_change()
      render_async(view, 2_000)
    end

    test "typing surfaces TMDB results; picking opens the title detail, never the plan flow", %{
      conn: conn
    } do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 246_810,
          "media_type" => "tv",
          "name" => "Sample Show",
          "first_air_date" => "2010-06-16"
        },
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      {:ok, view, html} = live(conn, "/discovery")
      assert html =~ "What do you want to watch?"

      html = search(view, "sample")
      assert html =~ "Sample Movie"
      assert html =~ "Sample Show"

      # Every pick lands on the title detail; Download lives inside it.
      view |> element("#omnibox-result-tv_series-246810") |> render_click()

      assert_patch(view, "/discovery?title=tv_series-246810")
      assert has_element?(view, "#detail-modal[data-state='open']", "Sample Show")
      refute has_element?(view, "#plan-modal[data-state='open']")

      await_supervised_tasks()
    end

    test "the results are page content: rows in the grid zone, the chips in the toolbar, the overview on the row",
         %{conn: conn} do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05",
          "overview" => "A sample movie overview."
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      html = search(view, "sample")

      # Rows live in the `grid` nav zone; the chip strip above them is the
      # page's `toolbar` zone (grid arithmetic needs the rows alone). No
      # floating overlay: a flat row has room for the overview.
      assert has_element?(view, "[data-nav-zone='grid'] #omnibox-result-movie-777")
      assert has_element?(view, "[data-nav-zone='toolbar'] #media-results-clear")
      assert html =~ "A sample movie overview."
      # The ref doubles as the overlay-restore origin.
      assert has_element?(view, "#omnibox-result-movie-777[data-entity-id='movie-777']")

      await_supervised_tasks()
    end

    test "a search result states what the library and the ladder already know", %{conn: conn} do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 424_242,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        },
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Owned Movie",
          "release_date" => "2010-03-05"
        },
        %{"id" => 888, "media_type" => "movie", "title" => "Other Movie", "release_date" => "2010-03-05"}
      ])

      {:ok, _intent} =
        Watchlist.put_rung(
          Title.new!(%{tmdb_id: 424_242, media_type: :movie, name: "Sample Movie"}),
          :list,
          nil
        )

      # A presentable movie (container + linked file) owning TMDB id 777.
      movie = create_standalone_movie(%{name: "Owned Movie"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "777"})
      create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "sample")

      assert has_element?(view, "#omnibox-result-movie-424242", "On your list")
      assert has_element?(view, "#omnibox-result-movie-777", "In library")
      refute has_element?(view, "#omnibox-result-movie-888", "In library")
      refute has_element?(view, "#omnibox-result-movie-888", "On your list")

      await_supervised_tasks()
    end

    test "an already-tracked title carries its ladder rung as a marker", %{conn: conn} do
      create_tracking_item(%{tmdb_id: 200, media_type: :tv_series, name: "Sample Show"})

      TmdbStubs.stub_search_multi([
        %{"id" => 200, "media_type" => "tv", "name" => "Sample Show", "first_air_date" => "2025-01-01"},
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2020-01-01"
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "sample")

      # `create_tracking_item/1` also puts the title on the ladder at Grab,
      # which the row states as Auto-grab.
      assert has_element?(view, "#omnibox-result-tv_series-200", "Auto-grab")
      refute has_element?(view, "#omnibox-result-movie-777", "Auto-grab")
      refute has_element?(view, "#omnibox-result-movie-777", "Tracking")
    end

    test "results render TMDB poster thumbnails, icon fallback without one", %{conn: conn} do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05",
          "poster_path" => "/sample-movie-poster.jpg"
        },
        %{
          "id" => 246_810,
          "media_type" => "tv",
          "name" => "Sample Show",
          "first_air_date" => "2010-06-16"
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "sample")

      assert has_element?(
               view,
               "#omnibox-result-movie-777 img[src='https://image.tmdb.org/t/p/w92/sample-movie-poster.jpg']"
             )

      # No poster on the TV result — icon placeholder, never a broken image.
      refute has_element?(view, "#omnibox-result-tv_series-246810 img")
    end

    test "a result a friend reviewed shows the review's glyph at the row's edge", %{conn: conn} do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      friend_secret = Secret.wrap(String.duplicate("0", 63) <> "3")
      friend_pubkey = "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
      {:ok, _} = Social.add_friend(friend_pubkey, "Sample Friend")
      title = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      event =
        Event.sign(
          Translation.to_event(:review, title, [text: nil, sentiment: :love], friend_pubkey),
          friend_secret
        )

      {:ok, _rec} = Activities.ingest(event)

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "sample")

      assert has_element?(
               view,
               "[data-nav-zone='grid'] .social-glyph[data-flag='love'][data-tip='Sample Friend loves this']"
             )

      await_supervised_tasks()
    end

    test "picking an upcoming row opens the title detail; listing then arming from there tracks it",
         %{conn: conn} do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 888,
          "media_type" => "movie",
          "title" => "Upcoming Movie",
          "release_date" => "2999-01-01"
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "upcoming")

      # The detail's preview and the arm's calendar both read the movie.
      TmdbStubs.stub_get_movie(
        888,
        TmdbStubs.movie_detail(%{
          "id" => 888,
          "title" => "Upcoming Movie",
          "release_date" => "2999-01-01"
        })
      )

      # Picking the upcoming row opens the title detail — no plan modal.
      view |> element("#omnibox-result-movie-888") |> render_click()

      assert_patch(view, "/discovery?title=movie-888")
      assert has_element?(view, "#detail-modal[data-state='open']", "Upcoming Movie")
      refute has_element?(view, "#plan-modal[data-state='open']")

      # A search result is not on the list: the one verb is Add to watchlist
      # (UIDR-039), and the tracking rows appear once it is listed.
      refute has_element?(view, "#detail-tracking-controls-track")
      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Watchlist.rung(888, :movie) == :list

      # Arming from there tracks it.
      view |> element("#detail-tracking-controls-track") |> render_click()
      await_supervised_tasks()
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert Watchlist.rung(888, :movie) == :follow
      assert ReleaseTracking.get_item_by_tmdb(888, :movie)
      assert Watchlist.listed?(888, :movie)
    end

    test "the upcoming/released chips scope the results; the active chip toggles back off", %{
      conn: conn
    } do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Released Movie",
          "release_date" => "2020-01-01"
        },
        %{
          "id" => 888,
          "media_type" => "movie",
          "title" => "Upcoming Movie",
          "release_date" => "2999-01-01"
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "movie")

      # Unscoped: both rows.
      assert has_element?(view, "#omnibox-result-movie-777")
      assert has_element?(view, "#omnibox-result-movie-888")

      view |> element("button[phx-click='omnibox_scope'][phx-value-scope='upcoming']") |> render_click()

      refute has_element?(view, "#omnibox-result-movie-777")
      assert has_element?(view, "#omnibox-result-movie-888")

      # Clicking the active chip returns to everything.
      view |> element("button[phx-click='omnibox_scope'][phx-value-scope='upcoming']") |> render_click()

      assert has_element?(view, "#omnibox-result-movie-777")
      assert has_element?(view, "#omnibox-result-movie-888")
    end

    test "an exhausted query renders the honest empty answer; Clear search resets it", %{conn: conn} do
      TmdbStubs.stub_search_multi([])

      {:ok, view, _html} = live(conn, "/discovery")
      html = search(view, "zzzz")
      assert html =~ "Nothing found on TMDB."

      # The results section carries its own reset — no click-away, no
      # overlay to lose; clearing the query is the one dismissal.
      view |> element("#media-results-clear") |> render_click()

      refute has_element?(view, "[data-component='media-results']")
    end

    test "an in-input X appears once a query is typed and clears the search", %{conn: conn} do
      TmdbStubs.stub_search_multi([])

      {:ok, view, _html} = live(conn, "/discovery")

      # Empty box — no X to click.
      refute has_element?(view, "#omnibox-media-clear")

      search(view, "zzzz")
      assert has_element?(view, "#omnibox-media-clear")

      view |> element("#omnibox-media-clear") |> render_click()

      refute has_element?(view, "#omnibox-media-clear")
      refute has_element?(view, "[data-component='media-results']")
    end

    test "the results show the full first TMDB page, not just eight", %{conn: conn} do
      TmdbStubs.stub_search_multi(
        for n <- 1..22 do
          %{
            "id" => 1000 + n,
            "media_type" => "movie",
            "title" => "Sample Movie #{n}",
            "release_date" => "2010-03-05"
          }
        end
      )

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "sample")

      # Result #9 was the first casualty of the old Enum.take(8) cap.
      assert has_element?(view, "#omnibox-result-movie-1009")
      assert has_element?(view, "#omnibox-result-movie-1020")
      # One TMDB page is the ceiling — depth past 20 is a query-refinement
      # problem, not a pagination problem.
      refute has_element?(view, "#omnibox-result-movie-1021")
    end

    test "a re-fire of the same effective query never searches TMDB again", %{conn: conn} do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      html = search(view, "sample")
      assert html =~ "Sample Movie"

      # Same query with a trailing space: poison the stub — any further
      # TMDB call fails loudly. The dedup memo must short-circuit.
      Req.Test.stub(:tmdb, fn _conn -> raise "TMDB searched twice for the same query" end)

      html =
        view
        |> form("form[phx-change='omnibox_change']", %{query: "sample "})
        |> render_change()

      refute html =~ "Searching TMDB"
      assert render(view) =~ "Sample Movie"
    end

    test "a rung set elsewhere refreshes the open modal's bookmark and the search rows", %{conn: conn} do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 246_810,
          "media_type" => "tv",
          "name" => "Sample Show",
          "first_air_date" => "2010-06-16"
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "sample")

      view |> element("#omnibox-result-tv_series-246810") |> render_click()
      assert_patch(view, "/discovery?title=tv_series-246810")
      assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='false']")
      refute has_element?(view, "#omnibox-result-tv_series-246810", "On your list")

      {:ok, _} =
        Watchlist.put_rung(
          Title.new!(%{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show"}),
          :list,
          nil
        )

      render_until(view, fn _html ->
        has_element?(view, "#detail-watchlist-toggle[aria-pressed='true']")
      end)

      # The rows' rungs ride the page's debounced shelf reload.
      render_until(
        view,
        fn _html -> has_element?(view, "#omnibox-result-tv_series-246810", "On your list") end,
        2_000
      )

      await_supervised_tasks()
    end

    test "a search result can be reviewed from its detail modal", %{conn: conn} do
      TmdbStubs.stub_search_multi([
        %{
          "id" => 424_242,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      {:ok, view, _html} = live(conn, "/discovery")
      search(view, "sample")

      view |> element("#omnibox-result-movie-424242") |> render_click()
      assert_patch(view, "/discovery?title=movie-424242")

      view |> element("#detail-review") |> render_click()
      assert has_element?(view, "#review-modal[data-state='open']", "Sample Movie")

      # Clicking Review puts the cursor in the text box for a pointer
      # user; keyboard and gamepad keep focus with the input system, so
      # the gate is `MouseAutofocus` rather than an unconditional focus.
      assert has_element?(view, "#review-modal #review-text[phx-hook='MouseAutofocus']")

      view |> element("#review-sentiment [phx-value-choice='love']") |> render_click()
      render_submit(view, "review_send", %{"text" => "Worth it"})

      refute has_element?(view, "#review-modal[data-state='open']")
      assert [%{tmdb_id: 424_242, sentiment: :love, text: "Worth it"}] = Activities.list_sent()

      await_supervised_tasks()
    end
  end
end
