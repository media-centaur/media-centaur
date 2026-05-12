defmodule MediaCentarrWeb.PageSmokeTest do
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

  use MediaCentarrWeb.ConnCase, async: false

  import MediaCentarr.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentarr.{Config, Secret}
  alias MediaCentarr.Watcher.FilePresence

  defp record_present(file), do: FilePresence.record_file(file.file_path, file.watch_dir)

  # Aggressive mount-time budget for every smoke. Media Centarr is a
  # local-first app; mounts should be near-instant. Steady-state mounts
  # observed locally cluster at 3–25ms. 60ms gives ~2× headroom — tight
  # enough to catch real regressions, loose enough to absorb routine
  # GC/scheduler jitter. Do not loosen casually.
  @render_budget_ms 60

  # Cold-start cost (BEAM JIT, schema caching, first-DB-query overhead)
  # is paid by whichever mount runs first. Without a warmup, that test
  # becomes flaky as the budget tightens. We pay the cold-start cost
  # once per `mix test` invocation and gate further runs with
  # :persistent_term so subsequent tests measure steady-state only.
  @warmup_flag {__MODULE__, :warmed_up?}

  setup %{conn: conn} = context do
    warmup_once(conn)
    context
  end

  defp warmup_once(conn) do
    if :persistent_term.get(@warmup_flag, false) do
      :ok
    else
      {:ok, _view, _html} = live(conn, "/")
      :persistent_term.put(@warmup_flag, true)
      :ok
    end
  end

  defp live_within!(conn, path, budget_ms \\ @render_budget_ms) do
    {micros, result} = :timer.tc(fn -> live(conn, path) end)
    ms = div(micros, 1000)

    if ms > budget_ms do
      flunk(
        "Page #{path} mount took #{ms}ms, exceeds budget of #{budget_ms}ms. " <>
          "This is a local app — mounts should be near-instant."
      )
    end

    result
  end

  for {path, label} <- [
        {"/", "home"},
        {"/library", "library browse"},
        {"/status", "status"},
        {"/settings", "settings"},
        {"/setup", "setup tour"},
        {"/review", "review"},
        {"/console", "console"},
        {"/history", "watch history"},
        {"/upcoming", "upcoming"}
      ] do
    test "#{label} (#{path}) renders without crashing", %{conn: conn} do
      assert {:ok, _view, html} = live_within!(conn, unquote(path))
      assert is_binary(html)
    end
  end

  describe "/library?selected=<id> with movie that has ISO 8601 duration" do
    # Detail-panel metadata row formats `entity.duration` (ISO 8601) for
    # display. Calling the wrong formatter on this string crashes the
    # whole LiveView (ArithmeticError in :erlang.div/2). This smoke
    # ensures the metadata-row duration path renders for a movie shaped
    # like real production data.
    setup do
      movie =
        create_standalone_movie(%{
          name: "Smoke Movie With Duration",
          duration: "PT1H55M",
          date_published: "2008-07-18",
          content_rating: "PG-13"
        })

      {:ok, movie: movie}
    end

    test "library detail panel mounts for a movie with ISO 8601 duration",
         %{conn: conn, movie: movie} do
      assert {:ok, _view, html} = live_within!(conn, ~p"/library?selected=#{movie.id}")
      assert is_binary(html)
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
          library_entity_id: tv.id,
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
      assert {:ok, _view, html} = live_within!(conn, ~p"/library?selected=#{tv.id}")
      # Confirm the upcoming-row data-role appears at least once — without
      # the typed `seasons_view` flowing through, no upcoming row would
      # render at all.
      assert html =~ "data-role=\"upcoming-episode-row\""
    end
  end

  describe "/library?selected=<id> with movie that has detected subtitles" do
    # SubtitlesRow renders a row from `WatchedFile.subtitle_tracks` (an
    # `{:array, :map}` Ecto field). A render-path bug — bad map-key
    # access, missing struct/string conversion, nil-language pattern
    # mismatch — would crash the modal mount. This smoke pins the
    # branch that has a non-empty subtitle list with a mix of known
    # languages and an unknown sidecar (the rare-but-real case).
    setup do
      movie = create_standalone_movie(%{name: "Smoke Movie With Subtitles"})

      create_linked_file(%{
        movie_id: movie.id,
        file_path: "/media/test/Smoke.Movie.With.Subtitles.mkv",
        subtitle_tracks: [
          %{"kind" => "embedded", "language" => "en", "source" => "stream:2"},
          %{"kind" => "sidecar", "language" => nil, "source" => "/media/test/forced.srt"}
        ]
      })

      {:ok, movie: movie}
    end

    test "library detail panel mounts when a linked file has subtitle_tracks",
         %{conn: conn, movie: movie} do
      assert {:ok, _view, html} = live_within!(conn, ~p"/library?selected=#{movie.id}")
      assert is_binary(html)
    end
  end

  describe "/?zone=upcoming with tracked-item fixtures" do
    # Fixture covers every shape the Active card path renders so a
    # render-time crash in any branch trips the smoke. Not data-correctness
    # — just "no clause / boolean / nil errors on the way to the screen".
    setup do
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

    test "upcoming zone renders without crashing", %{conn: conn} do
      # /?zone=upcoming redirects to /upcoming (HomeLive handles zone params).
      assert {:error, {:live_redirect, %{to: "/upcoming"}}} =
               live_within!(conn, "/?zone=upcoming")

      assert {:ok, _view, html} = live_within!(conn, "/upcoming")
      assert is_binary(html)
    end
  end

  describe "/download" do
    setup do
      original = :persistent_term.get({Config, :config}, %{})

      :persistent_term.put(
        {Config, :config},
        Map.merge(original, %{
          prowlarr_url: "http://prowlarr.test",
          prowlarr_api_key: Secret.wrap("test-key")
        })
      )

      MediaCentarr.Capabilities.save_test_result(:prowlarr, :ok)

      # Seed an active pursuit + linked target so the unified pursuits-with-
      # downloads zone exercises its non-trivial branches (card rendering,
      # release_title threading, no-match hint derivation). Per the
      # automated-testing skill: smoke fixtures must cover the branches a
      # representative user would see in production.
      {_pursuit, _target} =
        MediaCentarr.TestFactory.create_pursuit_with_target(%{
          tmdb_id: "smoke-download",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto",
          release_title: "Sample.Movie.2010.1080p.WEB-DL",
          status: "acquired"
        })

      # Seed a second pursuit in :exhausted state so the new History zone
      # exercises its rendered-row branch (default filter is :failed). An
      # empty-state-only smoke would miss a render-path crash on the
      # terminal-pursuit row template.
      {exhausted_pursuit, _target} =
        MediaCentarr.TestFactory.create_pursuit_with_target(%{
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
      |> MediaCentarr.Repo.update!()

      # Seed a SECOND exhausted pursuit with the same title and state so
      # the smoke exercises the new `PursuitGroup` render branch (count
      # ≥2 collapses into a group row). Without this, only the
      # single-row path would be smoked.
      {grouped_pursuit, _target} =
        MediaCentarr.TestFactory.create_pursuit_with_target(%{
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
      |> MediaCentarr.Repo.update!()

      on_exit(fn ->
        MediaCentarr.Capabilities.clear_test_result(:prowlarr)
        :persistent_term.put({Config, :config}, original)
      end)

      :ok
    end

    test "renders without crashing (Prowlarr configured and tested)", %{conn: conn} do
      assert {:ok, _view, html} = live_within!(conn, "/download")
      assert is_binary(html)
      # The seeded active pursuit must render its card, exercising the
      # PursuitRow component's no-match hint path (no queue item matches).
      assert html =~ "Sample Movie"
      # The History zone (default filter :failed) must render the
      # exhausted pursuit row. With two same-title same-state pursuits
      # seeded, the group-render path fires (header reads "2 episodes").
      assert html =~ "History"
      assert html =~ "Sample Show"
      assert html =~ "2 episodes"
    end
  end

  describe "/download?selected=:pursuit_id (pursuit detail modal)" do
    setup do
      original = :persistent_term.get({Config, :config}, %{})

      :persistent_term.put(
        {Config, :config},
        Map.merge(original, %{
          prowlarr_url: "http://prowlarr.test",
          prowlarr_api_key: Secret.wrap("test-key")
        })
      )

      MediaCentarr.Capabilities.save_test_result(:prowlarr, :ok)

      {:ok, pursuit} =
        MediaCentarr.Repo.insert(
          MediaCentarr.Acquisition.Pursuits.Pursuit.create_changeset(%{
            tmdb_id: "smoke",
            tmdb_type: "movie",
            title: "Sample Movie",
            origin: "auto"
          })
        )

      on_exit(fn ->
        MediaCentarr.Capabilities.clear_test_result(:prowlarr)
        :persistent_term.put({Config, :config}, original)
      end)

      %{pursuit_id: pursuit.id}
    end

    test "renders without crashing for an existing pursuit", %{
      conn: conn,
      pursuit_id: pursuit_id
    } do
      assert {:ok, _view, html} = live_within!(conn, "/download?selected=#{pursuit_id}")
      assert is_binary(html)
      assert html =~ "Sample Movie"
      assert html =~ ~s|data-state="open"|
    end

    test "renders not-found inside the modal for an unknown pursuit_id", %{conn: conn} do
      assert {:ok, _view, html} =
               live_within!(conn, "/download?selected=#{Ecto.UUID.generate()}")

      assert html =~ "Pursuit not found"
    end
  end
end
