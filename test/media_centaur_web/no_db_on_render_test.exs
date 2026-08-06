defmodule MediaCentaurWeb.NoDbOnRenderTest do
  @moduledoc """
  Locks the "no DB on render" contract that the in-memory projection
  architecture (ADR-041, Library Schema v2 Phase 3) ships.

  Every top-level LiveView mount path is exercised against a small but
  representative fixture and the number of `MediaCentaur.Repo` queries
  it issues is captured via `MediaCentaur.QueryCounter`. The per-page
  assertion is an explicit ceiling on the mount-time query budget — a
  baseline that's allowed to FALL but never RISE without a deliberate
  bump (and a comment explaining why).

  ## What this test is

  A regression net for the cohort of bugs where a refactor reintroduces
  a `Repo.preload`, a hidden `N+1`, or a per-card per-mount lookup in a
  hot LiveView. The test passes today with the architecture as-designed;
  if a future change makes the LibraryLive mount issue 20 queries
  instead of one, this test goes red.

  ## What this test is NOT

  Not a guarantee of zero queries — several pages legitimately read
  during mount:

    * Pages backed by **non-Library** contexts (Settings, Status,
      Acquisition, Pursuits) read from their own context tables. ADR-041
      scopes the projection architecture to Library; cross-context
      projections are explicitly out of scope (see Phase 3 plan).

    * Pages that load **per-request state from URL params** (e.g.
      `?selected=<id>` on /library) hydrate a single detail row.
      These are bounded reads — one row, one query, predictable cost —
      not a denial-of-projection failure mode.

  Each per-page assertion below carries a comment explaining its
  budget. If you bump a budget, update the comment.
  """

  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.QueryCounter

  defp seed_library_fixture do
    movie = create_standalone_movie(%{name: "Sample Movie A"})
    record_present(create_linked_file(%{movie_id: movie.id}))

    tv = create_tv_series(%{name: "Sample Show A"})
    season = create_season(%{tv_series_id: tv.id, season_number: 1})
    episode = create_episode(%{season_id: season.id, episode_number: 1})

    record_present(
      create_linked_file(%{
        tv_series_id: tv.id,
        file_path: "/media/sample/show.s01e01.mkv"
      })
    )

    %{movie: movie, tv: tv, season: season, episode: episode}
  end

  # The first mount of a `mix test` invocation pays cold-start cost
  # (Ecto schema cache warm-up, JIT, etc.). Subsequent mounts measure
  # steady state. We warm up once per case in a setup_all-equivalent
  # before measuring any budgets.
  @warmup_flag {__MODULE__, :warmed_up?}

  setup %{conn: conn} = context do
    warmup_once(conn)

    # The root layout's ArtworkWarmup prefetch hints read the Browse /
    # HeroCandidates projections on every initial render. Prime them so
    # mounts take the production (ETS) path — unprimed, the test-mode
    # fallback would run the browse + hero queries inside the counted
    # mount and misattribute them to every page's navigation budget.
    MediaCentaur.Library.Views.Browse.refresh_cache()
    MediaCentaur.Library.Views.HeroCandidates.refresh_cache()

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

  defp mount_and_assert(conn, path, budget, why) do
    {{:ok, _view, html}, queries} =
      QueryCounter.count(fn ->
        {:ok, view, html} = live(conn, path)
        {:ok, view, html}
      end)

    assert is_binary(html)

    if length(queries) > budget do
      flunk("""
      #{path} mount issued #{length(queries)} queries, exceeds budget #{budget}.

      Budget rationale: #{why}

      Queries observed:
      #{QueryCounter.format(queries)}
      """)
    end
  end

  # Post-Phase-7 no-op (legacy hook from the library-presence-unification campaign).
  defp record_present(_file), do: :ok

  describe "Library-backed pages — projection-fed, near-zero queries" do
    # The Library context owns four ADR-041 projections (Browse, Detail,
    # Search, ContinueWatching) plus the Pillar-2 watch-progress
    # GenServer. Pages whose render path is fully served by those
    # projections should mount with at most a small handful of queries —
    # whatever the LiveView hooks (EntityModal, SpoilerFreeAware,
    # CapabilitiesAware) cost. The exact number is a moving target as
    # the projections expand; what matters is the ceiling stays bounded.

    setup do
      _fixture = seed_library_fixture()
      :ok
    end

    test "GET / (home) mounts within budget", %{conn: conn} do
      # HomeLive renders Continue Watching, Recently Added, and Hero
      # Candidates — all three are ADR-041 projections. In test mode
      # the Cache.Worker isn't running for these projections so reads
      # fall back to DB queries; the budget bakes that worst-case
      # cold-path cost in. In production the same mount issues ~0
      # render-path queries (ETS lookups, not Repo calls).
      #
      # Budget headroom: under full-suite load the cache-miss DB
      # fallback can vary slightly above the steady-state baseline
      # (Settings/Capabilities/Controls per-key fall-throughs). The
      # ceiling exists to catch dramatic regressions (a mount jumping
      # to 200+ queries), not to enforce a perfect-condition baseline.
      mount_and_assert(
        conn,
        "/",
        60,
        "DB-fallback for 3 Library projections + on_mount hooks (test mode)"
      )
    end

    test "GET /library mounts within budget", %{conn: conn} do
      # Library Schema v2 Phase 3.1: LibraryLive reads from Views.Browse
      # (BrowseItem structs), Library.ProgressRecords.summaries/1, and
      # Library.Availability.available_for_ids/1 — three bounded reads.
      #
      # In **production** the Browse projection's Cache.Worker keeps
      # the ETS table warm, so `Views.browse/0` is a microsecond ETS
      # lookup and the only on-mount Repo cost is the bulk progress +
      # availability lookups (~6 queries) plus on_mount-hook settings
      # cache-miss reads in test mode (~5).
      #
      # In **test mode** the Cache.Worker isn't running, so
      # `Views.browse/0` falls back to a fresh `Browser.fetch_all_typed_entries/0`
      # build — that adds ~25 queries (per-type fetchers + preloads).
      #
      # Per ADR-051 the first-paint load now runs on BOTH the disconnected
      # (static) and connected renders. `live/2` exercises both, so the
      # bulk Browse + progress + availability load is counted twice here
      # (~72 observed). The doubled ceiling reflects that intentional
      # desktop trade — the query SET is unchanged, just run on both
      # renders — and still catches a real regression (a mount jumping to
      # 200+ queries).
      mount_and_assert(
        conn,
        "/library",
        90,
        "Views.Browse DB fallback + bulk progress + bulk availability + on_mount hooks, run on both the disconnected and connected renders (ADR-051; ~72 observed, test-mode only)"
      )
    end

    test "GET /history mounts within budget", %{conn: conn} do
      # Watch History reads from the WatchHistory context (events table)
      # — not a Library projection per se, but bounded by limit.
      mount_and_assert(
        conn,
        "/history",
        40,
        "WatchHistory.list_recent + on_mount hooks (settings cache-miss in test mode)"
      )
    end
  end

  describe "Cross-context pages — bounded per-context reads" do
    test "GET /status mounts within budget", %{conn: conn} do
      # Status surfaces media-dirs / availability / pipeline state —
      # cross-context, not a single projection. Each context reads its
      # own state. Bounded by the number of contexts surfaced, and in
      # test mode every Settings.get/1 falls through to a DB read
      # (the SettingsCache isn't running) — that inflates the count
      # relative to production AND varies with full-suite ordering
      # (observed 38–50; the variance is entirely settings_entries
      # lookups; the worst observed mount moved 45 → 50 after the Incoming
      # merge landed, and the exact mechanism behind the suite-order jitter
      # is unattributed — StatusLive's own query set is unchanged). 52
      # still trips on any per-row N+1 while absorbing the jitter.
      #
      # The Status.Views / ShellBadges projections are primed here so the
      # mount takes the production path (ETS / persistent_term reads);
      # unprimed, their test-mode fallbacks run the overview + storage +
      # badge queries inline in the mount process, which this counter
      # would misattribute to the navigation path.
      MediaCentaur.Status.Views.Overview.refresh_cache()
      MediaCentaur.Status.Views.Storage.refresh_cache()
      MediaCentaurWeb.ShellBadges.refresh_cache()
      on_exit(fn -> MediaCentaurWeb.ShellBadges.reset_cache() end)

      mount_and_assert(
        conn,
        "/status",
        52,
        "Cross-context status surfaces (settings cache-miss DB fallback in test mode)"
      )
    end

    test "GET /incoming mounts within budget", %{conn: conn} do
      # Incoming (the merged /upcoming + /download page, DDR-015) is a
      # ReleaseTracking + Acquisition surface, not Library. Phase 3
      # projections don't cover it; the LiveView reads both contexts.
      # Without Prowlarr configured (this fixture) the acquisition reads
      # are skipped and the mount is the forecast build: ReleaseTracking
      # releases + watching items + auto-grab/settings reads, run on both
      # the disconnected and connected renders (ADR-051).
      mount_and_assert(
        conn,
        "/incoming",
        40,
        "ReleaseTracking forecast reads + on_mount hooks (settings cache-miss in test mode)"
      )
    end

    test "GET /settings mounts within budget", %{conn: conn} do
      # Settings reads config + secret tables. Out of ADR-041 scope.
      # In test mode the SettingsCache isn't running so every
      # `Settings.get/1` call falls through to a DB read; the budget
      # tolerates that cold-path cost. In production a warm cache
      # collapses these to in-memory lookups.
      #
      # The Library-maintenance card's two health probes
      # (`missing_images_summary`, `blank_extra_names_count`) each run on
      # the disconnected + connected mount = +4 bounded aggregates total;
      # the budget absorbs them plus settings_entries cache-miss jitter.
      #
      # ReviewBadge (session-wide on_mount) adds two bounded counts
      # (pending review files + awaiting mappings) on each mount phase
      # = +4 aggregates on every page.
      #
      # The per-page backdrop preferences (LibraryBackdropAware +
      # IncomingBackdropAware on SettingsLive) add two settings keys, each
      # read on the disconnected + connected mount = +4 cache-miss reads.
      mount_and_assert(
        conn,
        "/settings",
        52,
        "Config + Secret reads + maintenance health counts + per-client connection-test reads (per-key cache-miss DB fallback in test mode)"
      )
    end

    test "GET /setup mounts within budget", %{conn: conn} do
      # ReviewBadge (session-wide on_mount) adds two bounded counts on
      # each mount phase = +4 aggregates on every page.
      mount_and_assert(conn, "/setup", 19, "Initial setup wizard — minimal reads")
    end

    test "GET /review mounts within budget", %{conn: conn} do
      mount_and_assert(
        conn,
        "/review",
        40,
        "Review context reads + on_mount hooks (settings cache-miss in test mode)"
      )
    end

    test "GET /console mounts within budget", %{conn: conn} do
      # Console is a debug surface backed by an in-memory buffer; no
      # DB reads expected on the render path.
      mount_and_assert(conn, "/console", 15, "Console in-memory buffer + on_mount hooks")
    end
  end

  describe "Detail modal — bounded per-request read" do
    setup do
      fixture = seed_library_fixture()
      {:ok, fixture}
    end

    test "GET /library?selected=<movie_id> mounts within budget", %{conn: conn, movie: movie} do
      # The detail modal hydrates a single entity by id. After Phase
      # 3.2 Task D the modal-open path reads from Views.Detail
      # (Pillar-2 ETS in production, ~5 queries via DB-fallback in
      # test mode). The budget here is dominated by the Views.Browse
      # cold-start build for the grid (Cache.Worker isn't running in
      # tests — Phase 3 follow-up: warm Browse in test setup).
      #
      # Per ADR-051 the first-paint grid load runs on both the disconnected
      # and connected renders, so `live/2` counts the Browse fallback build
      # twice (~106 observed). The doubled ceiling reflects that intentional
      # desktop trade.
      mount_and_assert(
        conn,
        "/library?selected=#{movie.id}",
        130,
        "Views.Browse DB-fallback grid + Views.Detail DB-fallback modal-open + bulk progress/availability, grid load run on both renders (ADR-051; ~106 observed, test-mode only)"
      )
    end
  end
end
