defmodule MediaCentaurWeb.LibraryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Discovery
  alias MediaCentaur.Library
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.Playback.{Events, ProgressBroadcaster}
  alias MediaCentaur.Playback.Events.{PlaybackFailed, PlaybackStateChanged, TrackOverrideChanged}

  describe "zone tabs removed" do
    test "library page has no zone tabs", %{conn: conn} do
      {:ok, view, html} = live_async!(conn, "/library")

      refute has_element?(view, "[data-nav-zone='zone-tabs']")
      refute has_element?(view, "[data-zone-tab]")
      refute html =~ "Continue Watching"
    end

    test "library page renders the catalog grid section", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/library")

      assert has_element?(view, "#browse")
    end

    test "catalog grid populates with entities on initial mount", %{conn: conn} do
      # Regression: zone-stripping in Phase 4.5 broke the stream-population
      # path. handle_params now must reset the stream when entries are
      # loaded for the first time, not only when tab/sort/filter change.
      movie = create_standalone_movie(%{name: "Initial Mount Fixture"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, _view, html} = live_async!(conn, "/library")

      assert html =~ "Initial Mount Fixture"
    end
  end

  describe "first paint (disconnected render) — no empty-state flash" do
    # Desktop-app rendering principle (UIDR-012): the static first render
    # served before the WebSocket connects must already carry real data.
    # Previously `ensure_loaded/1` gated `load_library/1` on
    # `connected?/1`, so the disconnected render showed the mount
    # placeholders (`counts: %{all: 0, ...}`, empty `:grid` stream) and the
    # heading flashed "0 movies · 0 shows" with an empty grid
    # until the socket connected and re-rendered. The read is a cheap local
    # build, so it must run on the first render too. `get/2` (not
    # `live_async!`) is deliberate — it exercises the static render the
    # browser actually paints first.
    test "static render shows real counts and a populated grid, not the 0 placeholder",
         %{conn: conn} do
      movie = create_standalone_movie(%{name: "First Paint Fixture"})
      _ = create_linked_file(%{movie_id: movie.id})

      html = conn |> get("/library") |> html_response(200)

      assert html =~ "First Paint Fixture",
             "grid must be populated on the disconnected first render"

      assert html =~ "1 movie",
             "heading count must reflect real data on the disconnected first render"

      refute html =~ "0 movies",
             "must not flash the 0-count placeholder before the socket connects"
    end
  end

  describe "sort=watched" do
    setup do
      # Creation order (Never → Yesterday → LastWeek) makes the default
      # :recent grid order differ from the watched order under either
      # inserted_at tie-break direction, so the assertions below can only
      # pass when the :watched sort actually applies.
      never_watched = create_standalone_movie(%{name: "Never Watched Movie"})
      _ = create_linked_file(%{movie_id: never_watched.id})

      newest_watched = create_standalone_movie(%{name: "Watched Yesterday Movie"})
      _ = create_linked_file(%{movie_id: newest_watched.id})

      backdate(
        create_watch_progress(%{
          movie_id: newest_watched.id,
          position_seconds: 100.0,
          duration_seconds: 1000.0
        }),
        :last_watched_at,
        ~U[2026-08-09 20:00:00Z]
      )

      # Completed titles still count as watched — unlike the in-progress
      # filter, the :watched sort must include them.
      older_watched = create_standalone_movie(%{name: "Watched Last Week Movie"})
      _ = create_linked_file(%{movie_id: older_watched.id})

      progress =
        create_watch_progress(%{
          movie_id: older_watched.id,
          position_seconds: 1000.0,
          duration_seconds: 1000.0
        })

      Library.ProgressRecords.mark_completed!(progress)
      backdate(progress, :last_watched_at, ~U[2026-08-03 20:00:00Z])

      :ok
    end

    test "?sort=watched orders by last watched descending, never-watched last", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/library?sort=watched")

      assert dom_position(html, "Watched Yesterday Movie") <
               dom_position(html, "Watched Last Week Movie")

      assert dom_position(html, "Watched Last Week Movie") <
               dom_position(html, "Never Watched Movie")
    end

    test "selecting Recently Watched in the sort dropdown patches to ?sort=watched",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/library")

      view
      |> element("[phx-click='toggle_sort']")
      |> render_click()

      view
      |> element("li[phx-value-sort='watched']")
      |> render_click()

      assert assert_patch(view) == "/library?sort=watched"
    end
  end

  describe "search excludes all results" do
    setup do
      movie = create_standalone_movie(%{name: "Findable Movie"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "a filter that matches nothing shows the no-matches state, not the scan prompt",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/library")

      html =
        view
        |> element("form[phx-change='filter']")
        |> render_change(%{filter_text: "zzzznomatch"})

      assert html =~ "No titles match",
             "an empty filter result must explain the filter excluded everything"

      assert html =~ "Clear filters"

      refute html =~ "Scan media directories",
             "must not offer to scan when the library has entries that a filter is hiding"

      refute html =~ "No media yet",
             "the empty-library copy is wrong when the library is non-empty"
    end

    test "clearing the filter from the no-matches state restores the grid", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/library")

      view
      |> element("form[phx-change='filter']")
      |> render_change(%{filter_text: "zzzznomatch"})

      view
      |> element("button[phx-click='reset_filters']")
      |> render_click()

      _ = assert_patch(view)

      assert render(view) =~ "Findable Movie"
    end

    test "the search box exposes a clear control once it holds text", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/library")

      view
      |> element("form[phx-change='filter']")
      |> render_change(%{filter_text: "Findable"})

      assert has_element?(view, "[phx-click='clear_filter']"),
             "a non-empty filter must offer an inline clear (×) affordance"
    end

    test "clear_filter empties the text filter but keeps the rest of the URL state",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/library?tab=movies")

      view
      |> element("form[phx-change='filter']")
      |> render_change(%{filter_text: "Findable"})

      # Consume the patch the filter change itself pushed so assert_patch
      # below sees the clear, not the typed query.
      _ = assert_patch(view)

      view
      |> element("button[phx-click='clear_filter']")
      |> render_click()

      patched_to = assert_patch(view)

      refute patched_to =~ "filter=", "clearing the search must drop the filter param"
      assert patched_to =~ "tab=movies", "clearing the search must preserve the active tab"
    end
  end

  describe "detail modal dismissal" do
    # Regression: clicking inside a sibling overlay (e.g. Console drawer)
    # must not dismiss the detail modal. The dismiss mechanism must
    # therefore be backdrop-scoped, not document-scoped (no phx-click-away
    # on the panel). These tests pin that wiring.

    setup do
      movie = create_standalone_movie(%{name: "Dismiss Fixture"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "clicking the backdrop closes the modal", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

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
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")
      refute has_element?(view, "#detail-modal [phx-click-away]")
    end
  end

  describe "Letterboxd link" do
    defp create_letterboxd_movie(attrs) do
      movie = create_standalone_movie(attrs)
      _ = create_linked_file(%{movie_id: movie.id})
      movie
    end

    test "movie detail links to the film's Letterboxd page", %{conn: conn} do
      movie = create_letterboxd_movie(%{name: "Letterboxd Fixture", tmdb_id: "603"})

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")
      assert has_element?(view, "#detail-modal a[href='https://letterboxd.com/tmdb/603']")
    end

    test "no link when the Letterboxd links setting is off", %{conn: conn} do
      movie = create_letterboxd_movie(%{name: "Letterboxd Fixture", tmdb_id: "603"})

      MediaCentaur.Settings.find_or_create_entry!(%{
        key: "letterboxd_links",
        value: %{"enabled" => false}
      })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")
      refute has_element?(view, "#detail-modal a[href='https://letterboxd.com/tmdb/603']")
    end

    test "no link for a TV series", %{conn: conn} do
      series = create_tv_series(%{name: "Letterboxd TV Fixture", tmdb_id: "604"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      _ =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Episode S1E1",
          duration_seconds: 1260,
          content_url: "/tv/letterboxd-fixture/s01e01.mkv"
        })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{series.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")
      refute has_element?(view, "#detail-modal a[href='https://letterboxd.com/tmdb/604']")
    end

    test "no link when the movie has no TMDB id", %{conn: conn} do
      movie = create_letterboxd_movie(%{name: "Unmatched Letterboxd Fixture"})

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")
      refute has_element?(view, "#detail-modal a[href^='https://letterboxd.com/tmdb/']")
    end
  end

  describe "watchlist toggle" do
    setup do
      TmdbStubs.setup_tmdb_client()
    end

    test "toggling adds then removes the movie from the watchlist", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Watchlist Fixture", tmdb_id: "605"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      view |> element("#detail-watchlist-toggle") |> render_click()

      assert Discovery.on_watchlist?(605, :movie)
      assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true']")

      view |> element("#detail-watchlist-toggle") |> render_click()

      refute Discovery.on_watchlist?(605, :movie)
      assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='false']")

      await_supervised_tasks()
    end

    test "toggling adds a TV series with the :tv_series media type", %{conn: conn} do
      series = create_tv_series(%{name: "Watchlist TV Fixture", tmdb_id: "606"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      _ =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Episode S1E1",
          content_url: "/tv/watchlist-fixture/s01e01.mkv"
        })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{series.id}")

      view |> element("#detail-watchlist-toggle") |> render_click()

      assert Discovery.on_watchlist?(606, :tv_series)

      await_supervised_tasks()
    end

    test "toggling from a collection modal watchlists the shown member movie", %{conn: conn} do
      # Two parts: a singleton collection is presented as the movie itself,
      # so a one-part fixture would silently test the standalone-movie path.
      collection = create_movie_series(%{name: "Watchlist Collection Fixture"})

      for {name, position, tmdb_id} <- [{"Part 1", 0, "607"}, {"Part 2", 1, "608"}] do
        part =
          create_movie(%{
            movie_series_id: collection.id,
            name: name,
            position: position,
            tmdb_id: tmdb_id
          })

        create_linked_file(%{movie_id: part.id})
      end

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      view |> element("#detail-watchlist-toggle") |> render_click()

      # The toggle acts on the member the panel shows (the default first
      # part), not the collection or any other member — pins the
      # gate-vs-action agreement through `watchlist_subject/2`.
      assert Discovery.on_watchlist?(607, :movie)
      refute Discovery.on_watchlist?(608, :movie)

      await_supervised_tasks()
    end

    test "no toggle when the title has no TMDB id", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Unmatched Watchlist Fixture"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(view, "#detail-modal[data-state='open']")
      refute has_element?(view, "#detail-watchlist-toggle")
    end
  end

  describe "detail modal view controls" do
    # The modal's view controls are a soft button and a Manage cog on Play's
    # own line. There is exactly ONE text control, in ONE slot: it offers
    # Cast from the root view and reads Back from anywhere else.
    #
    # That is what keeps "Back" in a fixed position. Until 2026-08-07 there
    # were two buttons, each relabelling itself to "Back" when its own view
    # was open, so the word moved between the second and third slot
    # depending on which sub-view was showing.
    #
    # A tab strip was tried in between and reverted — it spans the panel and
    # lands a band of chrome on the seam the eye crosses going from Play to
    # the episode list.

    setup do
      tv_series = create_tv_series(%{name: "View Control Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      _episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/view-control/s01e01.mkv"
        })

      movie = create_standalone_movie(%{name: "View Control Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      # Two parts: a singleton collection is presented as the movie itself,
      # so a one-part fixture would silently test the movie path.
      collection = create_movie_series(%{name: "View Control Collection"})

      for {name, position} <- [{"Part 1", 0}, {"Part 2", 1}] do
        part =
          create_movie(%{
            movie_series_id: collection.id,
            name: name,
            position: position,
            cast: [%{name: "#{name} Actor", character: "Lead", order: 0}]
          })

        create_linked_file(%{movie_id: part.id})
      end

      {:ok, tv_series: tv_series, movie: movie, collection: collection}
    end

    test "no tab strip — the seam below Play stays clear", %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      refute has_element?(view, "#detail-modal [role='tablist']")
      refute has_element?(view, "#detail-modal [role='tab']")
    end

    test "on the root view the control offers Cast", %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      assert has_element?(view, "[data-role='view-control']", "Cast")
      refute has_element?(view, "[data-role='manage-toggle'][aria-pressed='true']")
    end

    test "off the root view the same slot names the way back", %{conn: conn, tv_series: tv_series} do
      # "Episodes", not "Back" — the label says where you are going. "Back"
      # only says it is not here, and what it means changes per view.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=cast")

      assert has_element?(view, "[data-role='view-control']", "Episodes")
      refute has_element?(view, "[data-role='view-control']", "Cast")
    end

    test "the way back is named for its destination, not for the body", %{
      conn: conn,
      movie: movie
    } do
      # A bare movie's main view is its hero page, so Manage returns to
      # "Overview" — labelling it "Episodes" would be a lie, and it has no
      # episode list to name anyway.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      assert has_element?(view, "[data-role='view-control']", "Overview")
    end

    test "Manage shows its open state without changing any label", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      assert has_element?(view, "[data-role='manage-toggle'][aria-pressed='true']")
      assert has_element?(view, "[data-role='manage-toggle'][aria-label='Manage']")
      # The same slot is the way out of Manage too — one control, one meaning.
      assert has_element?(view, "[data-role='view-control']", "Episodes")
    end

    test "Cast encodes itself into the URL", %{conn: conn, tv_series: tv_series} do
      # Regression: build_modal_path/2 must encode `view=cast`, not just
      # `view=info`. Without it the selection round-trips through
      # `parse_view` and lands back on the body, making the control look dead.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      view |> element("[data-role='view-control']") |> render_click()

      assert_patched(view, ~p"/library?selected=#{tv_series.id}&view=cast")
    end

    test "the control returns to the root view rather than closing", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      view |> element("[data-role='view-control']") |> render_click()

      assert_patched(view, ~p"/library?selected=#{tv_series.id}")
      assert has_element?(view, "[data-role='view-control']", "Cast")
    end

    test "a movie with no extras offers Cast from its hero page", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      assert has_element?(view, "[data-role='view-control']", "Cast")
      assert has_element?(view, "[data-role='manage-toggle']")
    end

    test "a collection offers the selected member's Cast (UIDR-023)", %{
      conn: conn,
      collection: collection
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      assert has_element?(view, "[data-role='view-control']", "Cast")
    end

    test "a collection without extras names the way back Overview — the member hero is its main view",
         %{conn: conn, collection: collection} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}&view=info")

      assert has_element?(view, "[data-role='view-control']", "Overview")
    end

    test "Manage has its files on the first open, not one patch later", %{
      conn: conn,
      tv_series: tv_series
    } do
      # The file load used to be deferred until Manage was actually opened, so
      # the first press rendered an empty sheet and the files arrived as a
      # second patch. That reads as a flash: the sheet has nothing in it, so
      # the scrollport collapses to the top and snaps back once the content
      # lands. Loading with the modal costs a stat per file on open and buys a
      # Manage view that is right on its first frame.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      html = view |> element("[data-role='manage-toggle']") |> render_click()

      assert html =~ "s01e01.mkv",
             "Manage must render its file list in the same patch that opens it"
    end

    test "the controls share Play's nav row, so DOWN still enters the body", %{
      conn: conn,
      tv_series: tv_series
    } do
      # UIDR-019 rule 2: DOWN from the action row lands on the episode you
      # would resume. The controls are items of that row, reached by
      # LEFT/RIGHT.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      assert has_element?(
               view,
               "[data-nav-zone='detail_actions'] [data-role='view-control'][data-nav-item][tabindex='0']"
             )

      assert has_element?(
               view,
               "[data-nav-zone='detail_actions'] [data-role='manage-toggle'][data-nav-item][tabindex='0']"
             )
    end
  end

  describe "detail modal navigation contract (UIDR-019)" do
    # The modal navigates as two regions — an action row over the body of the
    # title — and the whole model rests on attributes this template writes and
    # `assets/js/input/` reads. Neither side can check the other: no JS test can
    # see the template, and no Elixir test runs the input system. These
    # assertions are the seam between them, so a rename on either side fails
    # here rather than silently in the user's hands.

    setup do
      tv_series = create_tv_series(%{name: "Nav Contract Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      _episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/nav-contract/s01e01.mkv"
        })

      {:ok, tv_series: tv_series}
    end

    test "the modal declares its navigation model", %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      assert has_element?(view, "#detail-modal[data-nav-overlay='detail']")
    end

    test "the action row and the body are separate nav zones", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # Both regions must exist and be populated: entry resolves to the first
      # populated one, so an unmarked action row would silently drop the cursor
      # into the episode list instead of onto Play.
      assert has_element?(view, "[data-nav-zone='detail_actions'] [data-nav-item]")
      assert has_element?(view, "[data-nav-zone='detail_list'] [data-nav-item]")
    end

    test "a season is a disclosure group with its state on the header", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # LEFT from an episode walks up to `[data-nav-group]` and collapses the
      # `[aria-expanded='true']` head it finds there.
      assert has_element?(view, "[data-nav-zone='detail_list'] [data-nav-group]")

      assert has_element?(
               view,
               "[data-nav-group] [data-nav-item][aria-expanded='true'][phx-click='toggle_season']"
             )
    end

    test "collapsing a season flips the header's expanded state", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      view |> element("[data-nav-group] [aria-expanded='true']") |> render_click()

      assert has_element?(view, "[data-nav-group] [data-nav-item][aria-expanded='false']")
    end

    test "the body opens on the episode Play would play", %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # `[data-resume-target]` is what the cursor seeds from when the list has
      # no remembered position — config names the selector, so it has to be on
      # a focusable row rather than an inner element.
      assert has_element?(view, "[data-nav-zone='detail_list'] [data-nav-item][data-resume-target]")
    end

    test "the list-wide details toggle is deliberately not on the keyboard path", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      assert has_element?(view, "[data-role='episode-details-toggle']")
      refute has_element?(view, "[data-role='episode-details-toggle'][data-nav-item]")
    end
  end

  describe "track override badge + reset" do
    setup do
      movie = create_standalone_movie(%{name: "Track Override Movie"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "Manage view shows the remembered-tracks badge when an override exists", %{
      conn: conn,
      movie: movie
    } do
      {:ok, _} =
        Library.MediaTrackOverrides.upsert(:movie, movie.id, %{
          audio_lang: "jpn",
          subtitle_lang: "eng"
        })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      html = render(view)
      assert html =~ "Remembered tracks"
      assert html =~ "Japanese audio"
      assert html =~ "English subtitles"
      assert html =~ "Reset to default"
    end

    test "no badge when the entity has no override", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      refute render(view) =~ "Remembered tracks"
    end

    test "Reset to default clears the override and drops the badge", %{conn: conn, movie: movie} do
      {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, %{audio_lang: "jpn"})

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")
      assert render(view) =~ "Remembered tracks"

      view |> element("button[phx-click='reset_track_override']") |> render_click()

      assert Library.MediaTrackOverrides.get(:movie, movie.id) == nil
      refute render(view) =~ "Remembered tracks"
    end

    test "TrackOverrideChanged broadcast surfaces the badge live without remount", %{
      conn: conn,
      movie: movie
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")
      refute render(view) =~ "Remembered tracks"

      # Simulate a mid-playback capture: the override lands in the DB and
      # the MpvSession broadcasts TrackOverrideChanged. The open modal
      # must reflect it without the user reopening.
      {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, %{audio_lang: "fra"})
      Events.broadcast(%TrackOverrideChanged{owner_type: :movie, owner_id: movie.id})

      html = render(view)
      assert html =~ "Remembered tracks"
      assert html =~ "French audio"
    end

    test "TrackOverrideChanged for a different entity is ignored", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      Events.broadcast(%TrackOverrideChanged{
        owner_type: :movie,
        owner_id: Ecto.UUID.generate()
      })

      refute render(view) =~ "Remembered tracks"
    end
  end

  describe "Manage view file facts" do
    # Canned ffprobe output — probing "succeeds" for every path. Same
    # shape as `FileMediaInfoTest.StubRunner`; local because each test
    # module owns its stubs.
    defmodule StubProbeRunner do
      def run(_executable, _args) do
        json =
          Jason.encode!(%{
            "streams" => [
              %{
                "codec_type" => "video",
                "codec_name" => "hevc",
                "width" => 3840,
                "height" => 2160,
                "disposition" => %{"attached_pic" => 0}
              },
              %{
                "codec_type" => "audio",
                "codec_name" => "truehd",
                "channels" => 8,
                "channel_layout" => "7.1"
              }
            ],
            "format" => %{
              "duration" => "6073.6",
              "tags" => %{"title" => "Sample.Movie.2024.2160p-GRP"}
            }
          })

        {json, 0}
      end
    end

    setup do
      # Application env is not covered by GlobalStateSandbox, so the stub
      # is restored by hand.
      previous = Application.get_env(:media_centaur, :media_probe_runner)
      Application.put_env(:media_centaur, :media_probe_runner, StubProbeRunner)
      on_exit(fn -> Application.put_env(:media_centaur, :media_probe_runner, previous) end)

      movie = create_standalone_movie(%{name: "Probed Movie"})
      file = create_linked_file(%{movie_id: movie.id})
      :ok = Library.MediaInfo.refresh(file.file_presence_id, file.file_path)

      {:ok, movie: movie}
    end

    test "file rows carry the probed container title and tech line", %{
      conn: conn,
      movie: movie
    } do
      # The file's own claims sit on its Manage row, next to the
      # filename-parsed badges — a renamed fake release stays visible.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      html = render(view)
      assert html =~ "Container title"
      assert html =~ "Sample.Movie.2024.2160p-GRP"
      assert html =~ "1h 41m · HEVC · 3840×2160 · TrueHD 7.1"
    end
  end

  describe "Manage ledger (collapsed folder groups)" do
    # Eight files across two folders — above the ≤6 auto-expand
    # threshold, so the ledger must open collapsed.
    setup do
      # TMDB capability on, so the toolbar renders Rematch/Refresh
      # artwork rather than the Settings hint. GlobalStateSandbox
      # restores the key — no hand-rolled backup (ADR-049 harness rule).
      :persistent_term.put({MediaCentaur.Capabilities, :ready_flags}, %{
        tmdb: true,
        prowlarr: false,
        download_client: false,
        acquisition: false
      })

      tv_series = create_tv_series(%{name: "Ledger Show"})

      for season <- 1..2, episode <- 1..4 do
        _ =
          create_linked_file(%{
            tv_series_id: tv_series.id,
            file_path: "/tv/ledger-show/Season #{season}/Sample.Show.S0#{season}E0#{episode}.mkv",
            media_dir: "/tv"
          })
      end

      {:ok, tv_series: tv_series}
    end

    test "a large inventory rests collapsed — group heads, no file rows", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      assert has_element?(view, "[data-role='file-group-head'][aria-expanded='false']")
      refute has_element?(view, "[data-role='manage-file-row']")
    end

    test "group heads are disclosure nav items inside a nav group", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      # Same TREE contract as the season accordion: LEFT/RIGHT read
      # `aria-expanded` on a `data-nav-item` head inside `data-nav-group`.
      # The ledger is its own `manage_list` zone — NOT `detail_list`:
      # cursor memory is keyed by context name, so sharing the episode
      # list's name let ledger activity clobber its remembered position.
      assert has_element?(
               view,
               "[data-nav-zone='manage_list'] [data-nav-group] [data-nav-item][data-role='file-group-head'][phx-click='toggle_file_group']"
             )

      refute has_element?(view, "[data-nav-zone='detail_list'] [data-role='file-group-head']")
    end

    test "expanding a group reveals its file rows sorted by filename", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      view
      |> element("[data-role='file-group-head'][phx-click='toggle_file_group']", "Season 1")
      |> render_click()

      assert has_element?(view, "[data-role='file-group-head'][aria-expanded='true']")
      assert has_element?(view, "[data-role='manage-file-row']")

      # Only the expanded group's rows render — season 2 stays a summary.
      html = render(view)
      assert html =~ "Sample.Show.S01E01.mkv"
      refute html =~ "Sample.Show.S02E01.mkv"
    end

    test "collapsing an expanded group hides its rows again", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      view
      |> element("[data-role='file-group-head']", "Season 1")
      |> render_click()

      assert has_element?(view, "[data-role='manage-file-row']")

      view
      |> element("[data-role='file-group-head'][aria-expanded='true']", "Season 1")
      |> render_click()

      refute has_element?(view, "[data-role='manage-file-row']")
    end

    test "a group head summarises its contents without expanding", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      # Count and size are on the collapsed row — scoped cleanup needs
      # neither expansion nor arithmetic.
      assert has_element?(view, "[data-role='file-group-head']", "4 files")
    end

    test "folder delete is reachable on the collapsed row", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      assert has_element?(
               view,
               "[data-role='file-group-head'] [data-nav-sub-item][phx-click='delete_folder_prompt']"
             )
    end

    test "the toolbar card carries tools and identity above the ledger", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      assert has_element?(view, "[data-role='manage-toolbar'] button[phx-click='delete_all_prompt']")
      assert has_element?(view, "[data-role='manage-toolbar'] button[phx-click='rematch']")

      assert has_element?(
               view,
               "[data-role='manage-toolbar'] button[phx-click='refresh_artwork']"
             )
    end

    test "the toolbar card is its own nav zone, beside the list — not rows of it", %{
      conn: conn,
      tv_series: tv_series
    } do
      # The card is a horizontal strip: DOWN must drop past it into the
      # ledger, with its buttons reachable by LEFT/RIGHT. That means a
      # TOOLBAR-typed `manage_tools` region (config.js overlays.detail),
      # never toolbar buttons walked as detail_list tree items.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      assert has_element?(
               view,
               "[data-nav-zone='manage_tools'] button[phx-click='delete_all_prompt']"
             )

      assert has_element?(view, "[data-nav-zone='manage_tools'] button[phx-click='rematch']")

      refute has_element?(
               view,
               "[data-nav-zone='manage_list'] button[phx-click='delete_all_prompt']"
             )

      # The ledger is its own manage_list tree; zones are siblings, never nested.
      assert has_element?(view, "[data-nav-zone='manage_list'] [data-role='file-group-head']")
      refute has_element?(view, "[data-nav-zone='manage_list'] [data-nav-zone='manage_tools']")
    end
  end

  describe "Manage ledger auto-expand for small inventories" do
    setup do
      movie = create_standalone_movie(%{name: "Small Inventory Movie"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "a movie's single file is visible at rest, not hidden behind a chevron", %{
      conn: conn,
      movie: movie
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      assert has_element?(view, "[data-role='file-group-head'][aria-expanded='true']")
      assert has_element?(view, "[data-role='manage-file-row']")
    end
  end

  describe "cast view navigation contract" do
    setup do
      # Mixed cast: one unlinked member (no TMDB page) among linked ones —
      # both card variants must be on the keyboard path.
      cast =
        [%{name: "Unlinked Member", character: "Sample Role 0", order: 0}] ++
          for i <- 1..29 do
            %{
              name: "Nav Cast Member #{i}",
              character: "Sample Role #{i}",
              order: i,
              tmdb_person_id: 7000 + i
            }
          end

      tv_series = create_tv_series(%{name: "Nav Cast Show", cast: cast})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      _episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/nav-cast/s01e01.mkv"
        })

      {:ok, tv_series: tv_series}
    end

    test "the cast body replaces the tree zone with its own spatial region", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=cast")

      # One body zone at a time — nav zones must never nest, so the cast
      # region swaps in for the tree rather than wrapping inside it.
      assert has_element?(view, "[data-nav-zone='detail_cast']")
      refute has_element?(view, "[data-nav-zone='detail_list']")
    end

    test "every cast card is on the keyboard path", %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=cast")

      assert has_element?(view, "[data-nav-zone='detail_cast'] a[data-nav-item][tabindex='0']")
      assert has_element?(view, "[data-nav-zone='detail_cast'] div[data-nav-item][tabindex='0']")
      # The paging disclosure keeps its place in the same region, and
      # activating it returns the cursor to the card it came from.
      assert has_element?(
               view,
               "[data-nav-zone='detail_cast'] [data-nav-item][data-nav-return-focus][phx-click='show_more_cast']"
             )
    end

    test "the episode list keeps the tree zone", %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      assert has_element?(view, "[data-nav-zone='detail_list']")
      refute has_element?(view, "[data-nav-zone='detail_cast']")
    end
  end

  describe "cast view paging" do
    setup do
      cast =
        for i <- 1..30 do
          %{name: "Cast Member #{i}", character: "Sample Role #{i}", order: i - 1}
        end

      tv_series = create_tv_series(%{name: "Big Cast Show", cast: cast})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      _episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/big-cast/s01e01.mkv"
        })

      {:ok, tv_series: tv_series}
    end

    test "one page of cast renders with a Show more disclosure counting the rest", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=cast")

      html = render(view)
      assert html =~ "Cast Member 24"
      refute html =~ "Cast Member 25"
      assert has_element?(view, "[phx-click='show_more_cast']", "Show more (6 more)")
    end

    test "Show more pages in the rest and the disclosure disappears", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=cast")

      view |> element("[phx-click='show_more_cast']") |> render_click()

      html = render(view)
      assert html =~ "Cast Member 30"
      refute has_element?(view, "[phx-click='show_more_cast']")
    end

    test "the play-target episode's cast leads; the rest page under Other episodes", %{
      conn: conn
    } do
      cast =
        for i <- 1..30 do
          %{
            name: "Counted Member #{i}",
            character: "Sample Role #{i}",
            order: i - 1,
            tmdb_person_id: 5000 + i,
            total_episode_count: 100 - i
          }
        end

      series = create_tv_series(%{name: "Partitioned Cast Show", cast: cast})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      _episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/partitioned/s01e01.mkv",
          cast_person_ids: [5001, 5003, 5030]
        })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{series.id}&view=cast")

      html = render(view)
      # Lead section renders in full, including the low-billed guest.
      assert has_element?(view, "#cast-grid-lead")
      assert html =~ "Counted Member 30"
      assert html =~ "Other episodes"
      # 27 non-members: 24 visible, 3 behind the disclosure.
      assert has_element?(view, "[phx-click='show_more_cast']", "Show more (3 more)")
      # Appearance counts render on the cards.
      assert html =~ "99 episodes"
    end

    test "a movie opens on its hero page; the Cast control leads to the grid", %{conn: conn} do
      cast =
        for i <- 1..10 do
          %{name: "Movie Cast Member #{i}", character: "Sample Role #{i}", order: i - 1}
        end

      movie = create_standalone_movie(%{name: "Casted Movie", cast: cast})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      # The main view is the orientation block alone — no cast grid.
      refute has_element?(view, "[data-nav-zone='detail_cast']")
      refute render(view) =~ "Movie Cast Member 1"

      view |> element("[data-role='view-control']", "Cast") |> render_click()

      html = render_async(view)
      assert html =~ "Movie Cast Member 10"
      assert has_element?(view, "[data-nav-zone='detail_cast']")

      # And the control now leads back to the hero page.
      assert has_element?(view, "[data-role='view-control']", "Overview")
    end

    test "paging resets when the modal switches entities", %{conn: conn, tv_series: tv_series} do
      other_cast =
        for i <- 1..30 do
          %{name: "Other Member #{i}", character: "Sample Role #{i}", order: i - 1}
        end

      other = create_tv_series(%{name: "Other Big Cast Show", cast: other_cast})
      other_season = create_season(%{tv_series_id: other.id, season_number: 1})

      _other_episode =
        create_episode(%{
          season_id: other_season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/other-big-cast/s01e01.mkv"
        })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=cast")
      view |> element("[phx-click='show_more_cast']") |> render_click()
      refute has_element?(view, "[phx-click='show_more_cast']")

      # Same mounted LiveView, different selection — the per-selection
      # reset in apply_modal_params/2 is what's under test, not a remount.
      # An entity switch always lands on the main view (entity_switched in
      # apply_modal_params), so the Cast view is re-entered via its control.
      render_patch(view, ~p"/library?selected=#{other.id}")
      render_async(view)

      view |> element("[data-role='view-control']", "Cast") |> render_click()

      html = render_async(view)
      assert html =~ "Other Member 24"
      refute html =~ "Other Member 25"
      assert has_element?(view, "[phx-click='show_more_cast']", "Show more (6 more)")
    end
  end

  describe "live updates from playback" do
    setup do
      movie = create_standalone_movie(%{name: "Live Update Movie"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "entity_progress_updated broadcast paints the progress bar without remount",
         %{conn: conn, movie: movie} do
      # Pin the live-update contract: when MpvSession persists progress and
      # ProgressBroadcaster fires, the LibraryLive grid card must reflect
      # the new progress without the user reloading the page. Without this,
      # users start a movie and the catalog still shows it as untouched.
      {:ok, view, html} = live_async!(conn, "/library")
      assert html =~ "Live Update Movie"
      refute html =~ "progress-fill"

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 600.0,
        duration_seconds: 1000.0
      })

      ProgressBroadcaster.broadcast(movie.id, nil)

      html = render(view)
      assert html =~ "progress-fill"
      assert html =~ "width: 60"
    end

    test "playback_state_changed broadcast surfaces the now-playing pulse",
         %{conn: conn, movie: movie} do
      # The pulse dot in the top-right of the card is a high-signal "this
      # is playing right now" indicator. It must light up the moment another
      # device reports playback, not on the next page load.
      {:ok, view, html} = live_async!(conn, "/library")
      refute html =~ "animate-pulse"

      Events.broadcast(%PlaybackStateChanged{
        entity_id: movie.id,
        state: :playing,
        now_playing: %{},
        started_at: DateTime.utc_now()
      })

      assert render(view) =~ "animate-pulse"
    end

    test "playback_failed broadcast renders an error flash",
         %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/library")

      Events.broadcast(%PlaybackFailed{
        entity_id: movie.id,
        reason: :file_not_found,
        payload: %{reason: :file_not_found, file_path: "/missing.mkv"}
      })

      assert render(view) =~ "flash"
    end
  end

  describe "toggle_watched updates the modal in real time" do
    # Regression: the watched-toggle on a TV episode wrote to the DB
    # but the modal didn't reflect the change without a reload, because
    # the broadcast's `changed_record` lacked the synthesised
    # `:playable_item` association that subscribers key by. This test
    # exercises the full path — click → DB write → broadcast → hook
    # merge → re-render — and asserts the episode flips state without
    # the user navigating away.

    setup do
      tv_series = create_tv_series(%{name: "Toggle Live Update Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/toggle-show/s01e01.mkv"
        })

      {:ok, tv_series: tv_series, episode: episode}
    end

    test "clicking the toggle flips the episode to watched without remount",
         %{conn: conn, tv_series: tv_series, episode: episode} do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # Season 1 holds the next episode, so it opens expanded and the
      # episode row (with its toggle) is on screen already
      # (2026-08-05 auto-orient design).
      html = render(view)

      assert html =~ "Mark watched"
      refute html =~ "Mark unwatched"

      view
      |> element(~s|button[phx-click="toggle_watched"][phx-value-container-id="#{episode.id}"]|)
      |> render_click()

      # The handler dispatches the DB write to a Task; wait for the
      # broadcast so we know the task has run before we render the LV.
      assert_receive {:entity_progress_updated, %{entity_id: entity_id}}, 1000
      assert entity_id == tv_series.id

      html = render(view)
      assert html =~ "Mark unwatched"
    end

    test "clicking again flips back to unwatched without remount",
         %{conn: conn, tv_series: tv_series, episode: episode} do
      # Seed an already-completed progress so the modal opens in the
      # `:watched` state and the toggle goes :watched → :unwatched.
      _ =
        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 0.0,
          duration_seconds: 0.0,
          completed: true
        })

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      # Seasons open collapsed (2026-08-04 orientation design) — expand
      # season 1 so the episode row (and its toggle) renders.
      html =
        view
        |> element(~s|button[phx-click="toggle_season"][phx-value-season="1"]|)
        |> render_click()

      assert html =~ "Mark unwatched"

      view
      |> element(~s|button[phx-click="toggle_watched"][phx-value-container-id="#{episode.id}"]|)
      |> render_click()

      assert_receive {:entity_progress_updated, _payload}, 1000

      html = render(view)
      assert html =~ "Mark watched"
    end
  end

  describe "collection modal — movie-first with poster rail (UIDR-023)" do
    # The collection modal renders the *selected member's* movie panel —
    # same component family as a standalone movie — with a poster rail
    # as the picker. Selecting never plays; Play targets the selected
    # member; Cast is the member's cast; the rail carries per-member
    # state plus the release-tracking overlay.

    setup do
      collection = create_movie_series(%{name: "Coherent Collection", tmdb_id: "888001"})

      [part_1, part_2] =
        for {name, position, date} <- [
              {"Coherent Part 1", 0, ~D[2010-01-01]},
              {"Coherent Part 2", 1, ~D[2013-01-01]}
            ] do
          part =
            create_movie(%{
              movie_series_id: collection.id,
              name: name,
              position: position,
              date_published: date,
              description: "#{name} synopsis: a rumour leads three siblings into the hills.",
              cast: [%{name: "#{name} Lead Actor", character: "Lead", order: 0}]
            })

          create_linked_file(%{movie_id: part.id})
          part
        end

      {:ok, collection: collection, part_1: part_1, part_2: part_2}
    end

    test "opens on the default member's panel with a poster rail",
         %{conn: conn, collection: collection, part_1: part_1, part_2: part_2} do
      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      # Unstarted collection → first member is the subject.
      assert html =~ "Coherent Part 1 synopsis"
      assert has_element?(view, ~s|button[phx-click="play"][phx-value-id="#{part_1.id}"]|)

      # No saga eyebrow over the title — the rail below already names
      # the collection and shows the selected tile (2026-08-13 revision
      # of UIDR-023).
      refute html =~ "Part 1 of 2"

      # Both members are rail tiles; the selected one is marked.
      assert has_element?(view, "#rail-tile-#{part_1.id}[data-selected]")
      assert has_element?(view, "#rail-tile-#{part_2.id}")
      refute has_element?(view, "#rail-tile-#{part_2.id}[data-selected]")
    end

    test "selecting a poster re-anchors the panel without starting playback",
         %{conn: conn, collection: collection, part_1: part_1, part_2: part_2} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      view
      |> element("#rail-tile-#{part_2.id}")
      |> render_click()

      assert_patch(view)
      html = render(view)

      assert html =~ "Coherent Part 2 synopsis"
      refute html =~ "Coherent Part 1 synopsis"
      assert has_element?(view, ~s|button[phx-click="play"][phx-value-id="#{part_2.id}"]|)
      assert has_element?(view, "#rail-tile-#{part_2.id}[data-selected]")
      refute has_element?(view, "#rail-tile-#{part_1.id}[data-selected]")

      # Selection is URL-reflected: a fresh mount restores it.
      {:ok, _view, restored_html} =
        live_async!(conn, ~p"/library?selected=#{collection.id}&movie=#{part_2.id}")

      assert restored_html =~ "Coherent Part 2 synopsis"
    end

    test "a stale movie param falls back to the default member",
         %{conn: conn, collection: collection} do
      {:ok, _view, html} =
        live_async!(conn, ~p"/library?selected=#{collection.id}&movie=#{Ecto.UUID.generate()}")

      assert html =~ "Coherent Part 1 synopsis"
    end

    # UIDR-025: activity surfaces present member movies as movies. Their
    # click contract is "open the collection modal pre-selected on this
    # movie" — carried by the member's own id as `selected`, which the
    # resolver routes to the collection. The pointed-at movie is the
    # selection; the resume-target ladder applies only when the modal is
    # entered without one.
    test "opening by a member movie's id pre-selects that member",
         %{conn: conn, part_2: part_2} do
      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{part_2.id}")

      assert html =~ "Coherent Part 2 synopsis"
      assert has_element?(view, "#rail-tile-#{part_2.id}[data-selected]")
    end

    test "an explicit movie param outranks the member-id implication",
         %{conn: conn, part_1: part_1, part_2: part_2} do
      {:ok, view, html} =
        live_async!(conn, ~p"/library?selected=#{part_2.id}&movie=#{part_1.id}")

      assert html =~ "Coherent Part 1 synopsis"
      assert has_element?(view, "#rail-tile-#{part_1.id}[data-selected]")
    end

    test "opens on the resume-target member mid-collection",
         %{conn: conn, collection: collection, part_1: part_1, part_2: part_2} do
      _ =
        create_watch_progress(%{
          movie_id: part_1.id,
          position_seconds: 0.0,
          duration_seconds: 0.0,
          completed: true
        })

      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      assert html =~ "Coherent Part 2 synopsis"
      assert has_element?(view, ~s|button[phx-click="play"][phx-value-id="#{part_2.id}"]|)

      # The watched member's tile carries its state.
      assert has_element?(view, "#rail-tile-#{part_1.id} [data-rail-state='watched']")
    end

    test "the play-line watched toggle addresses the selected member and flips live",
         %{conn: conn, collection: collection, part_1: part_1} do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      view
      |> element(~s|button[phx-click="toggle_watched"][phx-value-container-id="#{part_1.id}"]|)
      |> render_click()

      assert_receive {:entity_progress_updated, %{entity_id: entity_id}}, 1000
      assert entity_id == collection.id

      assert {:ok, %{completed: true}} =
               MediaCentaur.Library.ProgressRecords.fetch_for_container(:movie, part_1.id)

      assert has_element?(view, "#rail-tile-#{part_1.id} [data-rail-state='watched']")
    end

    test "the Cast view shows the selected member's cast and follows selection",
         %{conn: conn, collection: collection, part_2: part_2} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}&view=cast")

      html = render(view)
      assert html =~ "Coherent Part 1 Lead Actor"
      refute html =~ "Coherent Part 2 Lead Actor"

      view
      |> element("#rail-tile-#{part_2.id}")
      |> render_click()

      html = render(view)
      assert html =~ "Coherent Part 2 Lead Actor"
      refute html =~ "Coherent Part 1 Lead Actor"
    end

    test "a tracked collection's announced part is a muted rail tile, not selectable",
         %{conn: conn, collection: collection} do
      item =
        create_tracking_item(%{
          tmdb_id: 888_001,
          media_type: :movie,
          name: "Coherent Collection",
          library_container_type: :movie_series,
          library_container_id: collection.id
        })

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 45),
        title: "Coherent Part 3",
        part_tmdb_id: 900_888
      })

      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      assert has_element?(view, "[data-role='rail-upcoming']", "Coherent Part 3")
      refute has_element?(view, ~s|[data-role='rail-upcoming'][phx-click]|)

      # The upcoming tile itself is the saga-extent signal — there is no
      # eyebrow restating it.
      refute html =~ "Part 1 of 3"
    end

    test "collection-level extras render in the body below the rail",
         %{conn: conn, collection: collection} do
      create_extra(%{
        movie_series_id: collection.id,
        name: "Coherent Making-Of",
        content_url: "/media/test/coherent-extra.mkv"
      })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      assert has_element?(view, "[data-role='extra-row']", "Coherent Making-Of")
    end
  end

  describe "live updates from availability" do
    test "availability_changed broadcast does not crash and re-renders",
         %{conn: conn} do
      # When a media dir goes offline (USB unplug, NFS drop), the LV must
      # consume the broadcast and re-render. The banner itself depends on
      # Availability GenServer state mutations that the LV does not own,
      # so this test pins the LV-side contract: subscribe + handle_info
      # without crashing and with a clean re-render.
      movie = create_standalone_movie(%{name: "Availability Movie"})
      file = create_linked_file(%{movie_id: movie.id})

      {:ok, view, _html} = live_async!(conn, "/library")

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        "library:availability",
        {:availability_changed, file.media_dir, :unavailable}
      )

      assert render(view) =~ "Availability Movie"
    end
  end

  describe "refresh artwork action" do
    @cache_key {MediaCentaur.Capabilities, :ready_flags}

    setup do
      cache_backup = :persistent_term.get(@cache_key, :__unset)

      :persistent_term.put(@cache_key, %{
        tmdb: true,
        prowlarr: false,
        download_client: false,
        acquisition: false
      })

      on_exit(fn ->
        case cache_backup do
          :__unset -> :persistent_term.erase(@cache_key)
          flags -> :persistent_term.put(@cache_key, flags)
        end
      end)

      # Unidentified movie (no tmdb_id) → the click takes the no-HTTP
      # pre-check branch and flashes, so this test never touches TMDB.
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "clicking Refresh artwork on an unidentified movie flashes the Rematch hint", %{
      conn: conn,
      movie: movie
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      assert has_element?(view, "button[phx-click='refresh_artwork']")

      html = view |> element("button[phx-click='refresh_artwork']") |> render_click()

      assert html =~ "No TMDB match"
    end
  end

  describe "detail modal artwork lands while open" do
    # Regression: in production `load_modal_entry` reads the cached Detail
    # ETS projection, which the cache worker refreshes asynchronously
    # *after* `entities_changed`. Refreshing the open modal on the raw
    # `entities_changed` therefore re-read a stale (image-less) row, so a
    # placeholder never flipped to artwork without a page reload. The modal
    # must also react to the post-refresh `{:library_view_updated, :detail,
    # _}` event (the same projection-refresh signal the grid/home use).
    test "poster appears when the post-refresh detail event fires", %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, view, html} = live_async!(conn, ~p"/library?selected=#{movie.id}")
      refute html =~ "/media-images/#{movie.id}/poster.jpg"

      # Artwork finished downloading: the Image row now exists in the DB.
      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      # The Detail projection cache worker has refreshed and emits this.
      send(view.pid, {:library_view_updated, :detail, "any-playable-item-id"})

      assert render(view) =~ "/media-images/#{movie.id}/poster.jpg"
    end
  end

  describe "library card info toggle" do
    # The `library_show_card_info` Settings entry controls whether each
    # poster card renders its title + type/year footer beneath the image.
    # Default-on: when the entry is absent the footer renders. Live updates
    # flow via the `settings:updates` PubSub topic through the
    # `LibraryCardInfoAware` on_mount trait — no full re-mount required.

    alias MediaCentaur.LibraryCardInfo
    alias MediaCentaur.Settings
    alias MediaCentaur.Topics

    setup do
      movie = create_standalone_movie(%{name: "Card Info Fixture"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "footer text renders by default (no Settings entry)", %{conn: conn, movie: movie} do
      assert Settings.get_by_key(LibraryCardInfo.setting_key()) == nil

      {:ok, _view, html} = live_async!(conn, "/library")

      assert html =~ movie.name,
             "card title must render in the default-on state"
    end

    test "broadcast of `enabled: false` hides footer text on re-render",
         %{conn: conn, movie: movie} do
      {:ok, view, html} = live_async!(conn, "/library")

      assert html =~ movie.name

      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: LibraryCardInfo.setting_key(),
          value: %{"enabled" => false}
        })

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.settings_updates(),
        {:setting_changed, LibraryCardInfo.setting_key(), %{"enabled" => false}}
      )

      # Drain the message; broadcast is processed synchronously by the
      # LiveView's attached handle_info hook before the next render.
      _ = render(view)

      refute render(view) =~ movie.name,
             "card title must be suppressed when `enabled: false` is live-broadcast"
    end

    test "entry persisted with `enabled: false` hides footer text on first render",
         %{conn: conn, movie: movie} do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: LibraryCardInfo.setting_key(),
          value: %{"enabled" => false}
        })

      {:ok, _view, html} = live_async!(conn, "/library")

      refute html =~ movie.name,
             "card title must be suppressed when the persisted setting is `enabled: false`"
    end
  end

  describe "delete files runs async" do
    # Regression: deleting an entity's files ran inline in handle_event.
    # For a large entity (dozens of files / tens of GB, or a network
    # mount) that blocked the LiveView process — clicks did nothing and
    # the heartbeat timed out, dropping the socket (it looked like a
    # crash). Deletion now runs in an owned start_async task (ADR-049):
    # handle_event returns immediately and the result lands in
    # handle_async. This drives that path to completion and asserts the
    # records are gone and the modal closed.
    setup do
      movie = create_standalone_movie(%{name: "Async Delete Fixture"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "confirming delete-all removes the files and closes the modal", %{
      conn: conn,
      movie: movie
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      assert Library.Files.list_by_entity_id(movie.id) != [],
             "fixture must start with files on disk"

      # First click arms the inline confirm gesture.
      armed_html =
        view
        |> element("button[phx-click='delete_all_prompt']")
        |> render_click()

      assert armed_html =~ "Click again to confirm"

      # Second click hands the deletion to start_async; drain it.
      view
      |> element("button[phx-click='delete_all_prompt']")
      |> render_click()

      _ = render_async(view, 2_000)

      assert Library.Files.list_by_entity_id(movie.id) == [],
             "async delete must remove the watched-file records"

      patched_to = assert_patch(view)

      refute patched_to =~ "selected=",
             "modal must close (selection cleared) once no files remain"
    end

    # Regression: the hosts rendered `<.entity_modal>` without passing the
    # `deleting` assign, so the attr's nil default always won and the
    # confirmed button snapped back to its idle label while the async
    # delete ran — no feedback that anything was happening.
    test "second click shows the in-flight Deleting state until the async lands", %{
      conn: conn,
      movie: movie
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      view
      |> element("button[phx-click='delete_all_prompt']")
      |> render_click()

      # Second click arms `deleting` and hands off to start_async; this
      # render happens before the async result message is processed.
      deleting_html =
        view
        |> element("button[phx-click='delete_all_prompt']")
        |> render_click()

      assert deleting_html =~ "Deleting…"
      assert has_element?(view, "button[phx-click='delete_all_prompt'][disabled]")

      # Drain the async so teardown stays clean; modal closes on completion.
      _ = render_async(view, 2_000)
      _ = assert_patch(view)
    end
  end

  # Byte offset of a card title in the rendered document — cheap way to
  # assert relative grid order without parsing the DOM.
  defp dom_position(html, name) do
    {position, _length} = :binary.match(html, name)
    position
  end

  describe "play in place (UIDR-027)" do
    setup do
      movie = create_standalone_movie(%{name: "Playable Sample Movie"})
      _ = create_linked_file(%{movie_id: movie.id})
      %{movie: movie}
    end

    test "poster card carries a direct play button", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/library")

      assert has_element?(
               view,
               ~s|[data-entity-id="#{movie.id}"] button[phx-click="play"][phx-value-id="#{movie.id}"]|
             )
    end

    test "the card play button plays directly — no modal opens", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/library")

      view
      |> element(~s|[data-entity-id="#{movie.id}"] button[phx-click="play"]|)
      |> render_click()

      # The factory file has no bytes on disk, so reaching Playback.play/1
      # deterministically surfaces the file-not-available flash — proof the
      # click went straight to playback instead of routing through the modal.
      assert render(view) =~ "File not available"
      refute has_element?(view, "#detail-modal[data-state='open']")
    end

    test "a collection shelf card gets no play button", %{conn: conn} do
      # UIDR-025: a collection is filing, not content — the shelf never
      # plays. Two parts, so the singleton hoist doesn't present it as a
      # movie.
      collection = create_movie_series(%{name: "Sample Collection"})

      for {name, position} <- [{"Part 1", 0}, {"Part 2", 1}] do
        part =
          create_movie(%{movie_series_id: collection.id, name: name, position: position})

        create_linked_file(%{movie_id: part.id})
      end

      {:ok, view, _html} = live_async!(conn, "/library")

      refute has_element?(
               view,
               ~s|[data-entity-id="#{collection.id}"] button[phx-click="play"]|
             )
    end

    test "an autoplay URL param is inert — the modal opens without side effects",
         %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/library?selected=#{movie.id}&autoplay=1")

      assert has_element?(view, "#detail-modal[data-state='open']")
    end
  end

  describe "card play button toggle" do
    alias MediaCentaur.CardPlayButton
    alias MediaCentaur.Settings
    alias MediaCentaur.Topics

    setup do
      movie = create_standalone_movie(%{name: "Play Toggle Fixture"})
      _ = create_linked_file(%{movie_id: movie.id})
      {:ok, movie: movie}
    end

    test "play button renders by default (no Settings entry)", %{conn: conn, movie: movie} do
      assert Settings.get_by_key(CardPlayButton.setting_key()) == nil

      {:ok, view, _html} = live_async!(conn, "/library")

      assert has_element?(view, ~s|[data-entity-id="#{movie.id}"] button[phx-click="play"]|)
    end

    test "broadcast of `enabled: false` removes the play button on re-render",
         %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, "/library")

      assert has_element?(view, ~s|[data-entity-id="#{movie.id}"] button[phx-click="play"]|)

      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: CardPlayButton.setting_key(),
          value: %{"enabled" => false}
        })

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.settings_updates(),
        {:setting_changed, CardPlayButton.setting_key(), %{"enabled" => false}}
      )

      # Drain the message; broadcast is processed synchronously by the
      # LiveView's attached handle_info hook before the next render.
      _ = render(view)

      refute has_element?(view, ~s|[data-entity-id="#{movie.id}"] button[phx-click="play"]|)
    end

    test "entry persisted with `enabled: false` removes the play button on first render",
         %{conn: conn, movie: movie} do
      {:ok, _} =
        Settings.find_or_create_entry(%{
          key: CardPlayButton.setting_key(),
          value: %{"enabled" => false}
        })

      {:ok, view, _html} = live_async!(conn, "/library")

      refute has_element?(view, ~s|[data-entity-id="#{movie.id}"] button[phx-click="play"]|)
    end
  end
end
