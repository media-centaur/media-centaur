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

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.{Config, Secret}

  # These smokes mount each route and assert the key structural content
  # renders — a render-path crash (KeyError, FunctionClauseError, a bad
  # struct/string conversion) surfaces here instead of in a user's
  # browser. They make NO wall-clock timing assertions: per-mount
  # duration under concurrent test load is inherently noisy and a budget
  # gate flakes on the tail (ADR-049 — no timing assertions on noisy
  # quantities). Ongoing mount-time measurement lives in `scripts/profile`.

  for {path, label} <- [
        {"/", "home"},
        {"/library", "library browse"},
        {"/status", "status"},
        {"/status?subsystem=pipeline", "status subsystem drill-in"},
        {"/status?subsystem=self_update", "status self_update drill-in"},
        {"/status?subsystem=library", "status library drill-in"},
        {"/status?subsystem=system", "status system drill-in"},
        {"/settings", "settings"},
        {"/setup", "setup tour"},
        {"/review", "review"},
        {"/reconcile", "reconcile"},
        {"/console", "console"},
        {"/history", "watch history"}
      ] do
    test "#{label} (#{path}) renders without crashing", %{conn: conn} do
      assert {:ok, _view, html} = live_async!(conn, unquote(path))
      assert is_binary(html)
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
      assert {:ok, _view, html} = live_async!(conn, "/status?subsystem=library")
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
      assert {:ok, _view, html} = live_async!(conn, "/status?subsystem=system")
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
  for section <- ~w(system updates services preferences controls library tmdb
                    acquisition pipeline playback language release_tracking danger) do
    test "settings section #{section} renders without crashing", %{conn: conn} do
      assert {:ok, _view, html} = live_async!(conn, ~p"/settings?section=#{unquote(section)}")
      assert is_binary(html)
    end
  end

  # Post-Phase-7 no-op (legacy hook from the library-presence-unification campaign).
  defp record_present(_file), do: :ok

  describe "/library?selected=<id> with movie that has duration_seconds" do
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

      {:ok, movie: movie}
    end

    test "library detail panel mounts for a movie with duration_seconds",
         %{conn: conn, movie: movie} do
      assert {:ok, _view, html} = live_async!(conn, ~p"/library?selected=#{movie.id}")
      assert is_binary(html)
    end
  end

  describe "/?selected=<id> with a movie collection containing downloaded movies" do
    # Regression: the home detail panel renders `movie_row` for each
    # present constituent movie of a movie_series. `movie_row` reads
    # optional fields (:images, :description, :duration_seconds) that the
    # lean `DetailItem.movie_entry_to_map/1` projection map omits — a bare
    # dot-access raised `KeyError` and crashed HomeLive the moment a
    # collection with downloaded movies was opened. This smoke mounts the
    # home detail for exactly that shape and asserts a movie row renders.
    setup do
      series = create_movie_series(%{name: "Smoke Movie Collection"})
      # Two present child Movies — the hoist rule (ADR-050) presents a
      # collection AS a collection only when 2+ of its movies are owned (a
      # single owned movie is surfaced as the movie itself). Each linked
      # file auto-creates a present constituent the collection detail's
      # content_list/1 renders as a movie_row.
      _file1 = create_linked_file(%{movie_series_id: series.id, file_path: "/media/smoke/part-1.mkv"})
      _file2 = create_linked_file(%{movie_series_id: series.id, file_path: "/media/smoke/part-2.mkv"})

      {:ok, series: series}
    end

    test "home detail panel mounts and renders a movie row for a collection",
         %{conn: conn, series: series} do
      assert {:ok, _view, html} = live_async!(conn, ~p"/?selected=#{series.id}")
      assert is_binary(html)
      # Proves the movie_row branch actually rendered — a false-pass guard:
      # if the constituent movie weren't present, this smoke would silently
      # exercise nothing.
      assert html =~ ~s(data-role="movie-row")
    end
  end

  describe "/library?selected=<id> with TV series that has tracked upcoming releases" do
    # The TV-series detail page composes a typed `[%SeasonView{}]` from
    # both Library episodes and ReleaseTracking releases. A render-path
    # bug in any of the three EpisodeListItem variants (Library /
    # Missing / Upcoming) or in the future-season header crashes the
    # whole modal. This smoke pins the full cross-context render path:
    # an existing library season with a Missing slot replaced by an
    # Upcoming, plus a synthetic future season.
    setup do
      tv = create_tv_series(%{name: "Smoke Tracked Show"})

      record_present(
        create_linked_file(%{tv_series_id: tv.id, file_path: "/media/test/Smoke.S01E01.mkv"})
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
      assert {:ok, _view, html} =
               live_async!(conn, ~p"/library?selected=#{tv.id}")

      # Confirm the upcoming-row data-role appears at least once — without
      # the typed `seasons_view` flowing through, no upcoming row would
      # render at all.
      assert html =~ "data-role=\"upcoming-episode-row\""
    end
  end

  describe "/library?selected=<id> with movie that has detected subtitles" do
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
      assert {:ok, _view, html} = live_async!(conn, ~p"/library?selected=#{movie.id}")
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
      assert {:ok, _view, html} = live_async!(conn, ~p"/library")
      assert is_binary(html)
    end
  end

  describe "/incoming forecast-only (Prowlarr NOT configured) with tracked-item fixtures" do
    # The honest-degradation acceptance criterion (DDR-015): without
    # Prowlarr the merged page must MOUNT and render the forecast —
    # hero omnibox reframed to tracking plus the shelf — with no
    # acquisition sections. The fixture covers the release shapes the
    # forecast renders (TV episodes, streaming / theatrical / home-release
    # movies) so a render-time crash in any branch trips the smoke. Not
    # data-correctness — just "no clause / boolean / nil errors on the
    # way to the screen". Also pins the legacy `/?zone=upcoming` home
    # redirect onto the merged page.
    setup do
      # Belt-and-braces: guarantee the capability probe reads "not ready"
      # even if an earlier test leaked a green Prowlarr connection test.
      MediaCentaur.Capabilities.clear_test_result(:prowlarr)

      tv_item =
        create_tracking_item(%{
          tmdb_id: 9_001,
          media_type: :tv_series,
          name: "Smoke TV Show"
        })

      # Two released-not-in-library episodes — exercises the active-row
      # status-icon path AND the "Queue all N" button branch (renders only
      # when pending_grab_count >= 2 with acquisition_ready).
      Enum.each(1..2, fn episode ->
        create_tracking_release(%{
          item_id: tv_item.id,
          air_date: Date.add(Date.utc_today(), -3 - episode),
          season_number: 1,
          episode_number: episode,
          title: "Episode #{episode}",
          released: true
        })
      end)

      # Upcoming — exercises the upcoming-row path inside the same card
      create_tracking_release(%{
        item_id: tv_item.id,
        air_date: Date.add(Date.utc_today(), 7),
        season_number: 1,
        episode_number: 3,
        title: "Next Week",
        released: false
      })

      # Streaming movie — released, not in library
      streaming_movie =
        create_tracking_item(%{
          tmdb_id: 9_002,
          media_type: :movie,
          name: "Smoke Streaming Movie"
        })

      create_tracking_release(%{
        item_id: streaming_movie.id,
        air_date: Date.add(Date.utc_today(), -1),
        title: "Streaming",
        release_type: "digital",
        released: true
      })

      # Theatrical movie with NO home release dates — exercises the
      # "Home release: not yet announced" branch and is the exact shape
      # that previously crashed with `BadBooleanError` on the
      # `air_date and Date.compare(...)` expression.
      theatrical_movie =
        create_tracking_item(%{
          tmdb_id: 9_003,
          media_type: :movie,
          name: "Smoke Theatrical Movie"
        })

      create_tracking_release(%{
        item_id: theatrical_movie.id,
        air_date: Date.add(Date.utc_today(), -10),
        title: "Theatrical",
        release_type: "theatrical",
        released: true
      })

      # Theatrical movie WITH digital + physical release rows — exercises
      # the multi-line `home_release_lines/1` branch (Digital: …, Physical: …).
      home_release_movie =
        create_tracking_item(%{
          tmdb_id: 9_004,
          media_type: :movie,
          name: "Smoke Home Release Movie"
        })

      create_tracking_release(%{
        item_id: home_release_movie.id,
        air_date: Date.add(Date.utc_today(), -20),
        title: "Theatrical",
        release_type: "theatrical",
        released: true
      })

      create_tracking_release(%{
        item_id: home_release_movie.id,
        air_date: Date.add(Date.utc_today(), 30),
        title: "Digital",
        release_type: "digital",
        released: false
      })

      create_tracking_release(%{
        item_id: home_release_movie.id,
        air_date: Date.add(Date.utc_today(), 60),
        title: "Physical",
        release_type: "physical",
        released: false
      })

      :ok
    end

    test "forecast-only /incoming renders without crashing", %{conn: conn} do
      # /?zone=upcoming redirects to /incoming (HomeLive handles zone params).
      assert {:error, {:live_redirect, %{to: "/incoming"}}} =
               live_async!(conn, "/?zone=upcoming")

      assert {:ok, view, html} = live_async!(conn, "/incoming")
      assert is_binary(html)

      # Honest degradation: the hero mode hint reframes to tracking (the
      # hero has no prompt line), the shelf renders the seeded forecast,
      # and no acquisition section (in-flight pursuits, ledger) is on the
      # page.
      assert html =~ "to track their releases"
      assert has_element?(view, ~s([data-nav-zone="coming_up_list"]), "Smoke TV Show")
      refute html =~ ~s(data-nav-zone="pursuits")
      refute html =~ ~s(data-nav-zone="ledger")
    end
  end

  describe "/incoming (Prowlarr configured and tested)" do
    setup do
      original = :persistent_term.get({Config, :config}, %{})

      :persistent_term.put(
        {Config, :config},
        Map.merge(original, %{
          prowlarr_url: "http://prowlarr.test",
          prowlarr_api_key: Secret.wrap("test-key")
        })
      )

      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)

      # Seed a tracked upcoming release so the shelf renders an actual
      # card (poster tile, date badge, status pill) rather than only the
      # horizon terminus.
      shelf_item =
        create_tracking_item(%{
          tmdb_id: 9_101,
          media_type: :tv_series,
          name: "Smoke Shelf Show"
        })

      create_tracking_release(%{
        item_id: shelf_item.id,
        air_date: Date.add(Date.utc_today(), 4),
        season_number: 1,
        episode_number: 1,
        title: "Smoke Shelf Episode",
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

      exhausted_pursuit
      |> Ecto.Changeset.change(state: "exhausted")
      |> MediaCentaur.Repo.update!()

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

      grouped_pursuit
      |> Ecto.Changeset.change(state: "exhausted")
      |> MediaCentaur.Repo.update!()

      on_exit(fn ->
        MediaCentaur.Capabilities.clear_test_result(:prowlarr)
        :persistent_term.put({Config, :config}, original)
      end)

      :ok
    end

    test "renders without crashing (smart default — seeded activity wins)", %{conn: conn} do
      assert {:ok, view, html} = live_async!(conn, "/incoming")
      assert is_binary(html)

      # `IncomingLive.ensure_loaded/1` runs the pursuit-row + ledger +
      # history reads on the first render; `live_async!` drained any owned
      # async work at mount, so `render/1` reflects the loaded state.
      html = render(view)

      # The seeded active pursuit pulls the bare-path mount to Activity,
      # and its card exercises the PursuitRow component's no-match hint
      # path (no queue item matches).
      assert has_element?(view, ~s([data-nav-zone="zone-tabs"] .zone-tab-active), "Activity")
      assert html =~ "Sample Movie"
    end

    test "renders without crashing (?zone=coming_up)", %{conn: conn} do
      assert {:ok, view, html} = live_async!(conn, "/incoming?zone=coming_up")
      assert is_binary(html)

      # The explicit zone beats the smart default: the tab bar plus the
      # seeded tracked release's agenda row — the forecast branch, not
      # just the horizon.
      assert has_element?(view, ~s([data-nav-zone="zone-tabs"]))
      assert has_element?(view, ~s([data-nav-zone="coming_up_list"]), "Smoke Shelf Show")
    end

    test "renders without crashing (?zone=history)", %{conn: conn} do
      assert {:ok, view, _html} = live_async!(conn, "/incoming?zone=history")

      # The History tab IS the archive: filter chips + search render
      # immediately (no disclosure), default filter :all, and the two
      # same-title exhausted pursuits collapse into a group whose header
      # reads "2 episodes". Scoped to the ledger zone: a whole-page `=~`
      # also sweeps the Console drawer, whose GLOBAL log ring buffer
      # carries titles logged by earlier tests in the run.
      assert has_element?(view, "section[data-nav-zone='ledger'] [phx-click='set_history_filter']")
      assert has_element?(view, "section[data-nav-zone='ledger']", "Sample Show")
      assert has_element?(view, "section[data-nav-zone='ledger']", "2 episodes")
    end
  end

  describe "/incoming?selected=:pursuit_id (pursuit detail modal)" do
    setup do
      original = :persistent_term.get({Config, :config}, %{})

      :persistent_term.put(
        {Config, :config},
        Map.merge(original, %{
          prowlarr_url: "http://prowlarr.test",
          prowlarr_api_key: Secret.wrap("test-key")
        })
      )

      MediaCentaur.Capabilities.save_test_result(:prowlarr, :ok)

      {:ok, pursuit} =
        MediaCentaur.Repo.insert(
          MediaCentaur.Acquisition.Pursuits.Pursuit.create_changeset(%{
            tmdb_id: "smoke",
            tmdb_type: "movie",
            title: "Sample Movie",
            origin: "auto"
          })
        )

      on_exit(fn ->
        MediaCentaur.Capabilities.clear_test_result(:prowlarr)
        :persistent_term.put({Config, :config}, original)
      end)

      %{pursuit_id: pursuit.id}
    end

    test "renders without crashing for an existing pursuit", %{
      conn: conn,
      pursuit_id: pursuit_id
    } do
      assert {:ok, _view, html} = live_async!(conn, "/incoming?selected=#{pursuit_id}")
      assert is_binary(html)
      assert html =~ "Sample Movie"
      assert html =~ ~s|data-state="open"|
    end

    test "renders not-found inside the modal for an unknown pursuit_id", %{conn: conn} do
      assert {:ok, _view, html} =
               live_async!(conn, "/incoming?selected=#{Ecto.UUID.generate()}")

      assert html =~ "Pursuit not found"
    end
  end
end
