defmodule MediaCentaurWeb.LibraryLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Library
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

  describe "in_progress filter" do
    setup do
      # Movie the user has started but not finished
      in_progress_movie = create_standalone_movie(%{name: "In Progress Movie"})
      _ = create_linked_file(%{movie_id: in_progress_movie.id})

      create_watch_progress(%{
        movie_id: in_progress_movie.id,
        position_seconds: 100.0,
        duration_seconds: 1000.0
      })

      # Movie the user has fully completed
      finished_movie = create_standalone_movie(%{name: "Finished Movie"})
      _ = create_linked_file(%{movie_id: finished_movie.id})

      progress =
        create_watch_progress(%{
          movie_id: finished_movie.id,
          position_seconds: 1000.0,
          duration_seconds: 1000.0
        })

      Library.ProgressRecords.mark_completed!(progress)

      # Movie the user has never touched
      untouched_movie = create_standalone_movie(%{name: "Untouched Movie"})
      _ = create_linked_file(%{movie_id: untouched_movie.id})

      :ok
    end

    test "?in_progress=1 only shows entities with in-progress watch progress", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/library?in_progress=1")

      assert html =~ "In Progress Movie"
      refute html =~ "Finished Movie"
      refute html =~ "Untouched Movie"
    end

    test "?in_progress=1 shows the active-filter indicator chip", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/library?in_progress=1")
      assert html =~ "In progress"
    end

    test "/library (no param) shows all entities — no in-progress filter", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, "/library")

      assert html =~ "In Progress Movie"
      assert html =~ "Finished Movie"
      assert html =~ "Untouched Movie"
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

  describe "detail modal view controls" do
    # The modal's view controls are a soft button and a Manage cog on Play's
    # own line. There is exactly ONE text control, in ONE slot: it offers
    # More info from the root view and reads Back from anywhere else.
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
        part = create_movie(%{movie_series_id: collection.id, name: name, position: position})
        create_linked_file(%{movie_id: part.id})
      end

      {:ok, tv_series: tv_series, movie: movie, collection: collection}
    end

    test "no tab strip — the seam below Play stays clear", %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      refute has_element?(view, "#detail-modal [role='tablist']")
      refute has_element?(view, "#detail-modal [role='tab']")
    end

    test "on the root view the control offers More info", %{conn: conn, tv_series: tv_series} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      assert has_element?(view, "[data-role='view-control']", "More info")
      refute has_element?(view, "[data-role='manage-toggle'][aria-pressed='true']")
    end

    test "off the root view the same slot names the way back", %{conn: conn, tv_series: tv_series} do
      # "Episodes", not "Back" — the label says where you are going. "Back"
      # only says it is not here, and what it means changes per view.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=credits")

      assert has_element?(view, "[data-role='view-control']", "Episodes")
      refute has_element?(view, "[data-role='view-control']", "More info")
    end

    test "the way back is named for its destination, not for the body", %{
      conn: conn,
      movie: movie
    } do
      # A movie with no extras opens on More info, so that is where Manage
      # returns to — labelling it "Episodes" would be a lie, and it has no
      # episode list to name anyway.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=info")

      assert has_element?(view, "[data-role='view-control']", "More info")
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

    test "More info encodes itself into the URL", %{conn: conn, tv_series: tv_series} do
      # Regression: build_modal_path/2 must encode `view=credits`, not just
      # `view=info`. Without it the selection round-trips through
      # `parse_view` and lands back on the body, making the control look dead.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}")

      view |> element("[data-role='view-control']") |> render_click()

      assert_patched(view, ~p"/library?selected=#{tv_series.id}&view=credits")
    end

    test "the control returns to the root view rather than closing", %{
      conn: conn,
      tv_series: tv_series
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{tv_series.id}&view=info")

      view |> element("[data-role='view-control']") |> render_click()

      assert_patched(view, ~p"/library?selected=#{tv_series.id}")
      assert has_element?(view, "[data-role='view-control']", "More info")
    end

    test "a movie with no extras has nowhere else to offer", %{conn: conn, movie: movie} do
      # It opens on More info — that *is* its root — so the slot is empty and
      # the row is just Play and the cog.
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}")

      refute has_element?(view, "[data-role='view-control']")
      assert has_element?(view, "[data-role='manage-toggle']")
    end

    test "a collection has no More info to offer", %{conn: conn, collection: collection} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}")

      refute has_element?(view, "[data-role='view-control']")
    end

    test "a collection names its own body on the way back", %{conn: conn, collection: collection} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{collection.id}&view=info")

      assert has_element?(view, "[data-role='view-control']", "Movies")
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

    test "credits view shows the remembered-tracks badge when an override exists", %{
      conn: conn,
      movie: movie
    } do
      {:ok, _} =
        Library.MediaTrackOverrides.upsert(:movie, movie.id, %{
          audio_lang: "jpn",
          subtitle_lang: "eng"
        })

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=credits")

      html = render(view)
      assert html =~ "Remembered tracks"
      assert html =~ "Japanese audio"
      assert html =~ "English subtitles"
      assert html =~ "Reset to default"
    end

    test "no badge when the entity has no override", %{conn: conn, movie: movie} do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=credits")

      refute render(view) =~ "Remembered tracks"
    end

    test "Reset to default clears the override and drops the badge", %{conn: conn, movie: movie} do
      {:ok, _} = Library.MediaTrackOverrides.upsert(:movie, movie.id, %{audio_lang: "jpn"})

      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=credits")
      assert render(view) =~ "Remembered tracks"

      view |> element("button[phx-click='reset_track_override']") |> render_click()

      assert Library.MediaTrackOverrides.get(:movie, movie.id) == nil
      refute render(view) =~ "Remembered tracks"
    end

    test "TrackOverrideChanged broadcast surfaces the badge live without remount", %{
      conn: conn,
      movie: movie
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=credits")
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
      {:ok, view, _html} = live_async!(conn, ~p"/library?selected=#{movie.id}&view=credits")

      Events.broadcast(%TrackOverrideChanged{
        owner_type: :movie,
        owner_id: Ecto.UUID.generate()
      })

      refute render(view) =~ "Remembered tracks"
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
      |> element(~s|button[phx-click="toggle_watched"][phx-value-episode="#{episode.episode_number}"]|)
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
      |> element(~s|button[phx-click="toggle_watched"][phx-value-episode="#{episode.episode_number}"]|)
      |> render_click()

      assert_receive {:entity_progress_updated, _payload}, 1000

      html = render(view)
      assert html =~ "Mark watched"
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
  end
end
