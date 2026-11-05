defmodule MediaCentaurWeb.PageSmokeTest do
  @moduledoc """
  Visits every top-level LiveView route and asserts it mounts and renders
  without crashing. This is the cheapest possible safety net for the kind
  of bug where adding a new assign or template variable trips a
  `KeyError` only on a specific page.

  Each route (and each zone of the library page) gets one test. If a page
  needs additional setup to mount (Prowlarr config, DB fixtures, etc.)
  the setup happens in this file so the smoke test stays isolated from
  the per-page test files.

  Where a zone has a non-trivial render branch (e.g. the upcoming zone's
  Active cards with theatrical / streaming / TV variants), the test
  seeds enough fixture data to exercise that branch — empty-state
  rendering catches a different (smaller) class of bug.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.TmdbStubs

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Secret
  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Translation
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.TMDB.Title

  # These smokes mount each route and assert the key structural content
  # renders — a render-path crash (KeyError, FunctionClauseError, a bad
  # struct/string conversion) surfaces here instead of in a user's
  # browser. They make NO wall-clock timing assertions: per-mount
  # duration under concurrent test load is inherently noisy and a budget
  # gate flakes on the tail (ADR-049 — no timing assertions on noisy
  # quantities). Ongoing mount-time measurement lives in `scripts/profile`.

  # Every board subsystem gets a drill-in smoke; the list comes from the
  # board itself so a new subsystem (or a renamed key) cannot silently
  # fall back to the bare page and pass.
  @subsystem_routes for subsystem <- MediaCentaurWeb.StatusLive.HealthBoard.board_subsystems(),
                        do: {"/status?subsystem=#{subsystem}", "status #{subsystem} drill-in"}

  @guide_slug hd(MediaCentaur.Guide.chapters()).slug

  for {path, label} <-
        [
          {"/", "home"},
          {"/library", "library browse"},
          {"/status", "status"},
          {"/settings", "settings"},
          {"/setup", "setup tour"},
          {"/profiles", "profile picker"},
          {"/review", "review"},
          {"/episode-mapping", "episode-mapping"},
          {"/console", "console"},
          {"/console?subsystem=library", "console scoped to a subsystem"},
          {"/history", "watch history"},
          {"/guide", "guide index"},
          {"/guide/#{@guide_slug}", "guide chapter"},
          {"/apps", "apps"},
          {"/discovery", "discovery"},
          {"/watchlist", "watchlist"}
        ] ++ @subsystem_routes do
    test "#{label} (#{path}) renders without crashing", %{conn: conn} do
      assert {:ok, _view, html} = smoke!(conn, unquote(path))
      assert is_binary(html)
    end
  end

  # A smoke test mounts a page and leaves; the page's context-layer work —
  # searches, artwork, health probes — runs under the global task
  # supervisor and is this test's to drive to completion (ADR-049).
  defp smoke!(conn, path) do
    result = live_async!(conn, path)
    await_supervised_tasks()
    result
  end

  # The two review pages with work in every state they draw: a series
  # group with an importing file beside a pending one, a returned item with
  # its reason, a dismissed file under each list, and a show waiting in
  # episode mapping whose spine resolves off the LiveView process.
  describe "the review pages with work waiting" do
    setup do
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_routes([
        {"/tv/4242/season/1",
         TmdbStubs.season_detail(%{
           "season_number" => 1,
           "episodes" => [
             %{"episode_number" => 1, "name" => "Sample Special 2025", "air_date" => "2025-12-26"}
           ]
         })},
        {"/tv/4242", TmdbStubs.tv_detail(%{"id" => 4242, "seasons" => [%{"season_number" => 1}]})}
      ])

      importing =
        create_pending_file(%{
          file_path: "/media/test/Sample Show/S01E01.mkv",
          parsed_type: "tv",
          parsed_season: 1,
          parsed_episode: 1
        })

      {:ok, 1} = MediaCentaur.Review.approve([importing.id])

      create_pending_file(%{
        file_path: "/media/test/Sample Show/S01E02.mkv",
        parsed_type: "tv",
        parsed_season: 1,
        parsed_episode: 2
      })

      create_pending_file(%{
        file_path: "/media/test/Movie.A.2010.mkv",
        error_message: "Importing it failed. Approve it again to retry."
      })

      home_video = create_pending_file(%{file_path: "/media/test/Home.Video.mkv"})
      {:ok, 1} = MediaCentaur.Review.dismiss([home_video.id])

      {:ok, _} =
        MediaCentaur.EpisodeMapping.divert(%{
          file_path: "/media/test/Sample Show/Sample.Special.2025.mkv",
          media_dir: "/media/test",
          tmdb_id: 4242,
          series_title: "Sample Show",
          claimed_year: 2025
        })

      {:ok, dismissed} =
        MediaCentaur.EpisodeMapping.divert(%{
          file_path: "/media/test/Sample Show/Sample.Show.S03E01.mkv",
          media_dir: "/media/test",
          tmdb_id: 4242,
          claimed_season: 3,
          claimed_episode: 1
        })

      {:ok, _} = MediaCentaur.EpisodeMapping.dismiss_awaiting(dismissed)
      :ok
    end

    test "/review renders the waiting rows, their reasons and the view counts", %{conn: conn} do
      assert {:ok, view, _html} = smoke!(conn, "/review")
      html = render_async(view)

      assert html =~ "Dismissed · 1"
      assert html =~ "Not added"
    end

    test "/review?status=importing and ?status=dismissed render their views", %{conn: conn} do
      assert {:ok, importing, _html} = smoke!(conn, "/review?status=importing")
      assert render_async(importing) =~ "Importing"

      assert {:ok, dismissed, _html} = smoke!(conn, "/review?status=dismissed")
      assert render_async(dismissed) =~ "Dismissed"
    end

    test "/episode-mapping renders the show's mapping and the dismissed list", %{conn: conn} do
      assert {:ok, view, _html} = smoke!(conn, "/episode-mapping")
      html = render_async(view)

      assert html =~ "Dismissed (1)"
      assert html =~ "Sample Special 2025"
    end
  end

  # Social with a roster: a friend's listing on a title the library
  # owns (so a band paints the entity's backdrop and the rail has You and
  # a friend), an own review, and the Friends grid with a card opened by
  # the address.
  describe "/social with a roster" do
    @smoke_friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
    @smoke_friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

    setup do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.setup_artwork_cache()
      Identity.ensure()

      movie = create_standalone_movie(%{name: "Sample Movie 424242"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "424242"})
      create_linked_file(%{movie_id: movie.id})

      create_image(%{
        movie_id: movie.id,
        role: "poster",
        content_url: "#{movie.id}/poster.jpg",
        extension: "jpg"
      })

      create_image(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg",
        extension: "jpg"
      })

      {:ok, _friend} = Social.add_friend(@smoke_friend_pubkey, "Sample Friend")

      owned =
        Title.new!(%{tmdb_id: 424_242, media_type: :movie, name: "Sample Movie 424242", year: "2024"})

      at = System.os_time(:second)

      {:ok, _listing} =
        Activities.ingest(
          Event.sign(
            Translation.to_event(:listing, owned, [], @smoke_friend_pubkey,
              created_at: at,
              acted_at: at
            ),
            @smoke_friend_secret
          )
        )

      {:ok, _review} =
        Activities.review(
          Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie 777"}),
          :like,
          "mine"
        )

      :ok
    end

    for {path, label} <- [
          {"/social", "social feed"},
          {"/social?scope=friends", "social feed, friends scope"},
          {"/social?scope=you", "social feed, you scope"},
          {"/social/friends", "social friends"},
          {"/social/friends/you", "the reader's person page"},
          {"/social/friends/#{Social.to_npub(@smoke_friend_pubkey)}", "a friend's person page"}
        ] do
      test "#{label} (#{path}) renders without crashing", %{conn: conn} do
        assert {:ok, _view, html} = smoke!(conn, unquote(path))
        assert is_binary(html)
      end
    end
  end

  # The Social title detail modal is URL-driven (`?title=`); a listed
  # title for the ref makes the modal render on the Feed.
  describe "/social with the title modal open" do
    setup do
      # The modal warms the title's artwork through the TMDB client.
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.setup_artwork_cache()

      {:ok, _item} =
        MediaCentaur.Watchlist.put_rung(
          MediaCentaur.TMDB.Title.new!(%{
            tmdb_id: 777,
            media_type: :movie,
            name: "Sample Movie",
            release_date: ~D[2010-01-01]
          }),
          :list
        )

      :ok
    end

    for {path, label} <- [
          {"/social?title=movie-777", "social feed with the title modal"}
        ] do
      test "#{label} (#{path}) renders without crashing", %{conn: conn} do
        assert {:ok, view, html} = smoke!(conn, unquote(path))
        assert is_binary(html)
        assert Phoenix.LiveViewTest.has_element?(view, "#detail-modal")
      end
    end
  end

  # The library overview is the Library subsystem's drill-in Activity widget
  # (`/status?subsystem=library`). This seeds a library so the populated render
  # branches are exercised: the recently-added poster strip (glance card), a
  # review backlog (pending-work card), and all three completeness-gap rows
  # (missing artwork, missing metadata, season gap).
  describe "/status?subsystem=library with a populated library overview" do
    setup do
      movie =
        create_movie(%{name: "Sample Overview Movie", tmdb_id: "100", content_url: "/media/sample.mkv"})

      MediaCentaur.Library.FilePresence.stamp(
        "/media/sample.mkv",
        "/media",
        DateTime.utc_now(),
        size: 8_000_000_000
      )

      # Metadata gap — a container with no TMDB external id.
      create_movie(%{name: "Unmatched Overview Movie"})

      # Season gap — episodes 1 and 3, missing 2.
      series = create_tv_series(%{name: "Gappy Overview Show", tmdb_id: "200"})
      season = create_season(%{season_number: 1, tv_series_id: series.id})
      create_episode(%{episode_number: 1, season_id: season.id})
      create_episode(%{episode_number: 3, season_id: season.id})

      # Missing artwork — an image row whose cached file is absent on disk.
      create_image(%{
        owner_type: :movie,
        owner_id: movie.id,
        role: "poster",
        content_url: "/cache/missing-overview-poster.jpg"
      })

      # Review backlog.
      create_pending_file(%{file_path: "/media/incoming/overview-mystery.mkv"})

      :ok
    end

    test "library drill-in renders populated overview cards without crashing", %{conn: conn} do
      assert {:ok, _view, html} = smoke!(conn, "/status?subsystem=library")
      assert html =~ "Recently added"
      assert html =~ "Pending work"
      assert html =~ "Completeness gaps"
      assert html =~ "Storage outlook"
    end
  end

  # The retention panel renders per-policy sweep stats only once a run has
  # been recorded — seed one so the stats-bearing branch ("swept Xh ago ·
  # N removed") renders, not just the "not swept yet" resting state.
  describe "/status?subsystem=system with recorded retention runs" do
    setup do
      MediaCentaur.Retention.record_run(:diagnostic_events, 7)
      :ok
    end

    test "system drill-in renders the retention panel with sweep stats", %{conn: conn} do
      assert {:ok, _view, html} = smoke!(conn, "/status?subsystem=system")
      assert html =~ "Data retention"
      assert html =~ "7 removed"
    end
  end

  # Settings is a multi-section LiveView; each `?section=<id>` is effectively a
  # zone with its own render branch (the bare `/settings` smoke above only
  # exercises the default section). Mount every section so a section-specific
  # render crash — e.g. the gated Updates card, which renders nothing in the
  # default System view — surfaces here instead of in a user's browser. Keep in
  # sync with `MediaCentaurWeb.SettingsLive` @sections.
  for section <- ~w(system services preferences profiles controls players library tmdb social
                    acquisition import playback language maintenance danger) do
    test "settings section #{section} renders without crashing", %{conn: conn} do
      assert {:ok, _view, html} = smoke!(conn, ~p"/settings?section=#{unquote(section)}")
      assert is_binary(html)
    end
  end

  # Post-Phase-7 no-op (legacy hook from the library-presence-unification campaign).
  defp record_present(_file), do: :ok

  describe "/library?entity=<id> with movie that has duration_seconds" do
    # Detail-panel metadata row formats `entity.duration_seconds` (integer
    # seconds, post Library Schema v2 Phase 1 Task 3) for display. A
    # mismatched formatter would crash the whole LiveView; this smoke pins
    # the metadata-row duration path for a movie shaped like real production
    # data.
    setup do
      movie =
        create_standalone_movie(%{
          name: "Smoke Movie With Duration",
          duration_seconds: 6900,
          date_published: ~D[2008-07-18],
          content_rating: "PG-13"
        })

      # A title opens only with a present file; an address the library
      # cannot open is abandoned with a flash.
      _ = create_linked_file(%{movie_id: movie.id})

      {:ok, movie: movie}
    end

    test "library detail panel mounts for a movie with duration_seconds",
         %{conn: conn, movie: movie} do
      assert {:ok, _view, html} = smoke!(conn, ~p"/library?entity=#{movie.id}")
      assert is_binary(html)
    end
  end

  describe "/?entity=<id> with a movie collection containing downloaded movies" do
    # The home detail panel renders the movie-first collection modal
    # (UIDR-023): the selected member's panel over the poster rail. The
    # member subject and rail tiles read optional projection fields
    # (:images, :description, :duration_seconds) from the lean
    # `DetailItem.movie_entry_to_map/1` map — the historical KeyError
    # crash class this smoke pins (the row-based ancestor of this test
    # caught exactly that). Mounts the home detail for that shape and
    # asserts the rail actually rendered.
    setup do
      series = create_movie_series(%{name: "Smoke Movie Collection"})
      # Two present child Movies — the hoist rule (ADR-050) presents a
      # collection AS a collection only when 2+ of its movies are owned (a
      # single owned movie is surfaced as the movie itself). Each linked
      # file auto-creates a present constituent the collection rail
      # renders as a tile.
      _file1 = create_linked_file(%{movie_series_id: series.id, file_path: "/media/smoke/part-1.mkv"})
      _file2 = create_linked_file(%{movie_series_id: series.id, file_path: "/media/smoke/part-2.mkv"})

      {:ok, series: series}
    end

    test "home detail panel mounts and renders the member panel + rail for a collection",
         %{conn: conn, series: series} do
      assert {:ok, _view, html} = smoke!(conn, ~p"/?entity=#{series.id}")
      assert is_binary(html)
      # Proves the collection branch actually rendered — a false-pass
      # guard: if the constituent movies weren't present, this smoke
      # would silently exercise nothing.
      assert html =~ ~s(data-role="collection-rail")
      assert html =~ "rail-tile-"
      # The rail is a scroll row; its track keeps the nav zone.
      assert html =~ ~s(id="collection-rail-row")
      assert html =~ ~s(data-scroll-row-arrow="right")
      assert html =~ ~s(data-nav-zone="detail_rail")
    end
  end

  describe "/library?entity=<id> with TV series that has tracked upcoming releases" do
    # The TV-series detail page composes a typed `[%SeasonView{}]` from
    # both Library episodes and ReleaseTracking releases. A render-path
    # bug in any of the three EpisodeRow variants (Library /
    # Missing / Upcoming) or in the future-season header crashes the
    # whole modal. This smoke pins the full cross-context render path:
    # an existing library season with a Missing slot replaced by an
    # Upcoming, plus a synthetic future season.
    setup do
      tv = create_tv_series(%{name: "Smoke Tracked Show"})

      record_present(
        create_linked_file(%{tv_series_id: tv.id, file_path: "/media/test/Sample Title G2.S01E01.mkv"})
      )

      season =
        create_season(%{tv_series_id: tv.id, season_number: 1, number_of_episodes: 5, name: "S1"})

      _episode =
        create_episode(%{season_id: season.id, episode_number: 1, name: "Smoke Pilot"})

      item =
        create_tracking_item(%{
          tmdb_id: 7_777,
          name: "Smoke Tracked Show",
          library_container_type: :tv_series,
          library_container_id: tv.id,
          media_type: :tv_series
        })

      # Future episode in S1 (Upcoming row past number_of_episodes)
      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 7),
        season_number: 1,
        episode_number: 6,
        title: "Smoke Future S1E6",
        released: false
      })

      # Future season entirely (synthetic future-season bucket)
      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 30),
        season_number: 2,
        episode_number: 1,
        title: "Smoke Future S2E1",
        released: false
      })

      {:ok, tv: tv}
    end

    test "library detail panel mounts for a TV series with upcoming + future-season releases",
         %{conn: conn, tv: tv} do
      assert {:ok, view, _html} =
               smoke!(conn, ~p"/library?entity=#{tv.id}")

      # Seasons open collapsed (2026-08-04 orientation design), so
      # expand season 1 to exercise the upcoming-row render path.
      # Without the typed `seasons_view` flowing through, no upcoming
      # row would render at all.
      view
      |> element(~s|button[phx-click="toggle_season"][phx-value-season="1"]|)
      |> render_click()

      assert has_element?(view, "[data-role='upcoming-episode-row']")
    end
  end

  describe "/library?entity=<id> with movie that has detected subtitles" do
    # SubtitlesRow renders the language list aggregated from a movie's
    # linked-file tracks (`subtitles_tracks` table, owned by the
    # Subtitles context). A render-path bug — bad query, missing
    # struct/string conversion, nil-language pattern mismatch — would
    # crash the modal mount. This smoke pins the branch that has a
    # non-empty subtitle list with a mix of known languages and an
    # unknown sidecar (the rare-but-real case).
    setup do
      movie = create_standalone_movie(%{name: "Smoke Movie With Subtitles"})

      watched_file =
        create_linked_file(%{
          movie_id: movie.id,
          file_path: "/media/test/Smoke.Movie.With.Subtitles.mkv"
        })

      {:ok, _tracks} =
        MediaCentaur.Subtitles.replace_tracks_for_file(watched_file.id, [
          %{kind: :embedded, language: "en", source: "stream:2"},
          %{kind: :sidecar, language: nil, source: "/media/test/forced.srt"}
        ])

      {:ok, movie: movie}
    end

    test "library detail panel mounts when a linked file has subtitle tracks",
         %{conn: conn, movie: movie} do
      assert {:ok, _view, html} = smoke!(conn, ~p"/library?entity=#{movie.id}")
      assert is_binary(html)
    end
  end

  describe "/library with a populated grid and an in-progress title" do
    # The base /library smoke only ever renders the empty state. This one
    # seeds a present movie with partial watch progress so the grid's
    # poster-card path and the progress-driven sort/filter projection
    # actually render — a render-path crash surfaces here instead of in a
    # user's browser.
    setup do
      movie = create_standalone_movie(%{name: "Smoke Library Movie"})

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/test/Smoke.Library.Movie.mkv"
      })

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 60.0,
        duration_seconds: 600.0
      })

      :ok
    end

    test "library browse renders the grid and stat line", %{conn: conn} do
      assert {:ok, _view, html} = smoke!(conn, ~p"/library")
      assert is_binary(html)
    end
  end

  # The Watchlist page with a record of every kind it draws: a followed
  # series with an aired episode outstanding, a listed movie with a
  # digital release behind it, an owned title, an Ignored record, and
  # the title detail open on one of them.
  describe "/watchlist with records" do
    setup do
      TmdbStubs.setup_tmdb_client(self())

      item =
        create_tracking_item(%{
          tmdb_id: 246_810,
          media_type: :tv_series,
          name: "Sample Show",
          rung: :follow
        })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 1,
        episode_number: 1,
        air_date: Date.add(Date.utc_today(), -3)
      })

      create_title_intent(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie", rung: :list})
      create_title_intent(%{tmdb_id: 778, media_type: :movie, name: "Dismissed Movie", rung: :ignored})
      movie = create_standalone_movie(%{name: "Owned Movie"})
      create_external_id(%{source: "tmdb", external_id: "779", movie_id: movie.id})
      create_linked_file(%{movie_id: movie.id})
      create_title_intent(%{tmdb_id: 779, media_type: :movie, name: "Owned Movie", rung: :grab})
      :ok
    end

    test "renders without crashing", %{conn: conn} do
      assert {:ok, view, _html} = smoke!(conn, "/watchlist")
      assert has_element?(view, "#watchlist-group-follow")
      assert has_element?(view, "#watchlist-group-ignored")
    end

    test "renders without crashing with the title detail open", %{conn: conn} do
      assert {:ok, _view, html} = smoke!(conn, "/watchlist?title=tv_series-246810")
      assert html =~ "Sample Show"
    end
  end

  describe "/downloads without Prowlarr" do
    # UIDR-015 (amended 2026-11-02): without Prowlarr the page MOUNTS and
    # renders its diagnosed empty state (UIDR-034) — no search box, no
    # tabs, no acquisition section — instead of navigating away.
    setup do
      # Belt-and-braces: guarantee the capability probe reads "not ready"
      # even if an earlier test leaked a green Prowlarr connection test.
      MediaCentaur.Capabilities.clear_test_result(:prowlarr)
      :ok
    end

    test "/downloads renders its gap state without crashing", %{conn: conn} do
      assert {:ok, view, html} = smoke!(conn, "/downloads")
      assert is_binary(html)

      assert has_element?(view, "#downloads-empty", "Connect Prowlarr to search and download")
      refute has_element?(view, "#omnibox-release-input")
      refute html =~ ~s(data-nav-zone="pursuits")
      refute html =~ ~s(data-nav-zone="ledger")
    end
  end

  describe "/downloads (Prowlarr configured and tested)" do
    setup do
      config = :persistent_term.get({Config, :config}, %{})

      :persistent_term.put(
        {Config, :config},
        Map.merge(config, %{
          prowlarr_url: "http://prowlarr.test",
          prowlarr_api_key: Secret.wrap("test-key")
        })
      )

      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)
      # /downloads probes indexer health on mount; a configured Prowlarr is
      # asked, so it must answer.
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      # Seed a tracked upcoming release so the title address opens a title
      # carrying a next release (date, release, status pill) rather than
      # the empty state.
      watchlist_item =
        create_tracking_item(%{
          tmdb_id: 9_101,
          media_type: :tv_series,
          name: "Smoke Watchlist Show"
        })

      create_tracking_release(%{
        item_id: watchlist_item.id,
        air_date: Date.add(Date.utc_today(), 4),
        season_number: 1,
        episode_number: 1,
        title: "Smoke Watchlist Episode",
        released: false
      })

      # Seed an active pursuit + linked target so the unified pursuits-with-
      # downloads zone exercises its non-trivial branches (card rendering,
      # release_title threading, no-match hint derivation). Per the
      # automated-testing skill: smoke fixtures must cover the branches a
      # representative user would see in production.
      {_pursuit, _target} =
        MediaCentaur.TestFactory.create_pursuit_with_target(%{
          tmdb_id: "smoke-download",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto",
          release_title: "Sample.Movie.2010.1080p.WEB-DL",
          status: "acquired"
        })

      # Seed a second pursuit in :exhausted state so the terminal-pursuit
      # surfaces exercise their rendered-row branches — the open ledger
      # ("Recently landed") and the History zone (default filter is
      # :failed). An empty-state-only smoke would miss a render-path
      # crash on the terminal-pursuit row templates.
      {exhausted_pursuit, _target} =
        MediaCentaur.TestFactory.create_pursuit_with_target(%{
          tmdb_id: "smoke-history",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 3,
          origin: "auto",
          release_title: "Sample.Show.S01E03.1080p.WEB-DL",
          status: "failed"
        })

      MediaCentaur.TestFactory.force_state(exhausted_pursuit, "exhausted")

      # Seed a SECOND exhausted pursuit with the same title and state so
      # the smoke exercises the new `PursuitGroup` render branch (count
      # ≥2 collapses into a group row). Without this, only the
      # single-row path would be smoked.
      {grouped_pursuit, _target} =
        MediaCentaur.TestFactory.create_pursuit_with_target(%{
          tmdb_id: "smoke-history-group",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 4,
          origin: "auto",
          release_title: "Sample.Show.S01E04.1080p.WEB-DL",
          status: "failed"
        })

      MediaCentaur.TestFactory.force_state(grouped_pursuit, "exhausted")

      %{watchlist_item: watchlist_item}
    end

    test "renders without crashing (Activity, the bare path)", %{conn: conn} do
      assert {:ok, view, html} = smoke!(conn, "/downloads")
      assert is_binary(html)

      # `DownloadsLive.ensure_loaded/1` runs the pursuit-row + ledger +
      # history reads on the first render; `live_async!` drained any owned
      # async work at mount, so `render/1` reflects the loaded state.
      html = render(view)

      # The seeded active pursuit pulls the bare-path mount to Activity,
      # and its card exercises the PursuitRow component's no-match hint
      # path (no queue item matches).
      assert has_element?(view, ~s([data-nav-zone="zone-tabs"] .zone-tab-active), "Activity")
      assert html =~ "Sample Movie"
    end

    test "renders without crashing (?title= opens the title modal)", %{
      conn: conn,
      watchlist_item: watchlist_item
    } do
      assert {:ok, view, _html} =
               smoke!(conn, "/downloads?title=tv_series-#{watchlist_item.tmdb_id}")

      assert has_element?(view, "#detail-modal[data-state=open]")
      assert has_element?(view, "#detail-modal", "Smoke Watchlist Show")
    end

    test "renders without crashing (?zone=history)", %{conn: conn} do
      assert {:ok, view, _html} = smoke!(conn, "/downloads?zone=history")

      # The History tab IS the archive: filter chips + search render
      # immediately (no disclosure), default filter :all, and the two
      # same-title exhausted pursuits collapse into a group whose header
      # reads "2 episodes". Scoped to the ledger zone: a whole-page `=~`
      # also sweeps the Console drawer, whose GLOBAL log ring buffer
      # carries titles logged by earlier tests in the run.
      assert has_element?(view, "section[data-nav-zone='ledger'] #ledger-filter")
      assert has_element?(view, "section[data-nav-zone='ledger']", "Sample Show")
      assert has_element?(view, "section[data-nav-zone='ledger']", "2 episodes")
    end
  end

  describe "/downloads?selected=:pursuit_id (pursuit detail modal)" do
    setup do
      config = :persistent_term.get({Config, :config}, %{})

      :persistent_term.put(
        {Config, :config},
        Map.merge(config, %{
          prowlarr_url: "http://prowlarr.test",
          prowlarr_api_key: Secret.wrap("test-key")
        })
      )

      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)
      # /downloads probes indexer health on mount; a configured Prowlarr is
      # asked, so it must answer.
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      {:ok, pursuit} =
        MediaCentaur.Repo.insert(
          MediaCentaur.Acquisition.Pursuits.Pursuit.create_changeset(%{
            tmdb_id: "smoke",
            tmdb_type: "movie",
            title: "Sample Movie",
            origin: "auto"
          })
        )

      %{pursuit_id: pursuit.id}
    end

    test "renders without crashing for an existing pursuit", %{
      conn: conn,
      pursuit_id: pursuit_id
    } do
      assert {:ok, _view, html} = smoke!(conn, "/downloads?selected=#{pursuit_id}")
      assert is_binary(html)
      assert html =~ "Sample Movie"
      assert html =~ ~s|data-state="open"|
    end

    test "renders not-found inside the modal for an unknown pursuit_id", %{conn: conn} do
      assert {:ok, _view, html} =
               smoke!(conn, "/downloads?selected=#{Ecto.UUID.generate()}")

      assert html =~ "Download not found"
    end
  end

  describe "/apps with apps present" do
    setup do
      MediaCentaur.Features.set(:apps, true)
      create_app(%{name: "Sample Smoke App"})
      :ok
    end

    test "renders the card grid", %{conn: conn} do
      assert {:ok, _view, html} = smoke!(conn, "/apps")
      assert html =~ "Sample Smoke App"
    end
  end
end
