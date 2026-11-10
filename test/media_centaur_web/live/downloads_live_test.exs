defmodule MediaCentaurWeb.DownloadsLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.TitleDownloadParams
  alias MediaCentaur.Activities
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Watchlist
  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaurWeb.DownloadsLive.SearchSession
  alias MediaCentaur.Acquisition.Pursuits.Units
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.Acquisition.{Target, TargetEvents}
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Activities.Translation
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Social
  alias MediaCentaur.Secret
  alias MediaCentaur.TMDB.Title

  # `DownloadsLive.ensure_loaded/1` defers the initial reads (search
  # session, capability flag, active pursuit rows, history rows) to an
  # owned `start_async(:acquisition_load, …)` (ADR-049). `render_async/1`
  # awaits it deterministically — no wall-clock sleep.
  defp render_after_async_load(view) do
    render_async(view, 2_000)
  end

  defp stub_prowlarr_with(results) do
    Req.Test.stub(:prowlarr, fn conn ->
      Req.Test.json(conn, results)
    end)
  end

  defp sample_release(opts \\ []) do
    %{
      "guid" => Keyword.get(opts, :guid, "guid-1"),
      "title" => Keyword.get(opts, :title, "Sample.Show.S01E01.1080p.WEB-DL.mkv"),
      "indexerId" => 1,
      "size" => 1_073_741_824,
      "seeders" => 42,
      "leechers" => 0,
      "indexer" => "Test Indexer",
      "publishDate" => "2026-04-01T00:00:00Z"
    }
  end

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      Map.merge(config, %{
        prowlarr_url: "http://prowlarr.test",
        prowlarr_api_key: Secret.wrap("test-key"),
        download_client_type: "qbittorrent",
        download_client_url: "http://qb.test"
      })
    )

    # The page's acquisition sections are gated on explicit green
    # connection tests for Prowlarr (and the queue section on the download
    # client). Seed both so tests of other behaviors see the fully-enabled page.
    Capabilities.save_test_result(:prowlarr, :ok)
    Capabilities.save_test_result(:download_client, :ok)

    :ok
  end

  describe "mount" do
    test "the Heads-up glyph names a failing Prowlarr hand-off", %{conn: conn} do
      # What the grab that met "cannot reach the download client" reports,
      # kept fresh by the probe while down — past the incident's grace.
      IntegrationAvailability.report(
        {:handoff, :usenet},
        {:down, :client_unavailable},
        now: DateTime.add(DateTime.utc_now(), -600, :second)
      )

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      assert has_element?(view, "#needs-attention-client", "Prowlarr can't hand releases")
    end

    # UIDR-015 (amended 2026-11-02): capability gating is render-level.
    # The page MOUNTS without Prowlarr and says what it needs (UIDR-034)
    # — the search box, the tabs and the sections wait for the indexer.
    test "without Prowlarr the page says what it needs instead of its sections", %{conn: conn} do
      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        Map.merge(config, %{prowlarr_url: nil, prowlarr_api_key: nil})
      )

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      assert has_element?(view, "#downloads-empty", "Connect Prowlarr to search and download")
      assert has_element?(view, "#downloads-empty a[href='/settings?section=acquisition']")
      refute has_element?(view, "#omnibox-release-input")
      refute has_element?(view, "[data-nav-zone='zone-tabs']")
      refute has_element?(view, "[data-nav-zone='pursuits']")
      refute has_element?(view, "[data-nav-zone='ledger']")
    end

    test "a configured but untested Prowlarr is the same gap", %{conn: conn} do
      Capabilities.clear_test_result(:prowlarr)

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      assert has_element?(view, "#downloads-empty", "Connect Prowlarr to search and download")
      refute has_element?(view, "#omnibox-release-input")
      refute has_element?(view, "[data-nav-zone='pursuits']")
    end

    test "hides the active-downloads queue when the download client is untested",
         %{conn: conn} do
      Capabilities.clear_test_result(:download_client)

      {:ok, view, html} = live_async!(conn, ~p"/downloads")

      # Scoped to the live-activity zones — a whole-page `=~ "Downloading"`
      # refute also sweeps the Console drawer, whose GLOBAL log ring buffer
      # carries lines logged by earlier tests in the run (order-dependent
      # false match; same lesson as the page smoke).
      refute has_element?(view, "[data-nav-zone='pursuits']")
      refute has_element?(view, "[data-nav-zone='other_downloads']")
      assert html =~ "Connect a download client"
    end

    test "renders the page when Prowlarr is configured", %{conn: conn} do
      {:ok, view, html} = live_async!(conn, ~p"/downloads")

      assert html =~ "Downloads"
      # The release search box is the page's front door; no heading above it.
      assert has_element?(view, "[data-nav-zone='omnibox'] #omnibox-release-input")
      assert has_element?(view, "[data-page-behavior='downloads']")
      # The default-zone value is the LAYOUT KEY in input config.js, not a
      # context within it — `"pursuits"` here once left the page's nav graph
      # empty and keyboard/gamepad navigation dead.
      assert has_element?(view, "[data-nav-default-zone='downloads']")
    end

    test "first paint (disconnected render) reflects loaded capability, not the unloaded default",
         %{conn: conn} do
      # Desktop first-paint correctness: setup marks :download_client :ok, so
      # the load (which runs on the disconnected render) must surface the
      # enabled queue section. The previously-gated behavior left
      # `download_client_ready` at its mount default (false) on the static
      # render and flashed the "Connect a download client" empty state.
      html = conn |> get(~p"/downloads") |> html_response(200)

      refute html =~ "Connect a download client",
             "download-client capability must be loaded on the disconnected first paint"
    end
  end

  describe "a down Prowlarr" do
    setup %{conn: conn} do
      test_pid = self()

      Req.Test.stub(:prowlarr, fn conn ->
        send(test_pid, {:prowlarr_called, conn.request_path})

        case conn.request_path do
          "/api/v1/indexer" ->
            Req.Test.json(conn, [%{"id" => 1, "name" => "Indexer A", "enable" => true}])

          _other ->
            Req.Test.json(conn, [])
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")
      flush_prowlarr_calls()

      {:ok, view: view}
    end

    defp flush_prowlarr_calls do
      receive do
        {:prowlarr_called, _path} -> flush_prowlarr_calls()
      after
        0 -> :ok
      end
    end

    test "the periodic health read asks nobody while Prowlarr is down", %{view: view} do
      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      render_async(view, 2_000)
      flush_prowlarr_calls()

      send(view.pid, :refresh_storage)
      render_async(view, 2_000)

      refute_received {:prowlarr_called, _path}
    end

    test "Prowlarr coming back re-reads the roster; a hand-off change is not this page's", %{
      view: view
    } do
      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      render_async(view, 2_000)
      flush_prowlarr_calls()

      send(view.pid, {:integration_availability_changed, {:handoff, :usenet}, :up})
      assert render(view)
      refute_received {:prowlarr_called, _path}

      {:changed, _state} = IntegrationAvailability.report(:prowlarr, :up)

      assert_receive {:prowlarr_called, "/api/v1/indexer"}, 2_000
    end
  end

  describe "query_change" do
    test "updates expansion preview for valid syntax", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      html =
        view
        |> form("form[phx-change='query_change']", query: "Sample Show S01E{01-10}")
        |> render_change()

      assert html =~ "10 queries in parallel"
    end

    test "shows error for invalid brace syntax", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      html =
        view
        |> form("form[phx-change='query_change']", query: "foo {a-}")
        |> render_change()

      assert html =~ "Invalid brace syntax"
    end
  end

  describe "search submit is never gated by a disabled button" do
    # History: the release form's submit button used to be `disabled`
    # whenever the (debounced) expansion preview was `:idle` or
    # `{:error, _}`. A *disabled default submit button silently swallows
    # the Enter key* (HTML implicit-submission rule) — the intermittent
    # "Enter doesn't search, I have to click the button" bug. The button
    # is now gone entirely (release mode mirrors media mode: Enter is the
    # only submit path), which makes that bug class unrepresentable.
    # `submit_search` still guards empty/invalid queries server-side.

    test "the release form has no submit button — Enter is the only submit path", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      refute has_element?(view, "section[data-nav-zone='omnibox'] button[type='submit']")
    end

    test "submitting a fresh valid query starts a search (Enter path)", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [sample_release(title: "Movie.A.2024.2160p.BluRay")])

          _ ->
            Req.Test.json(conn, [])
        end
      end)

      # Submit directly from the freshly-mounted page (preview still `:idle`,
      # mirroring an Enter pressed before the debounce flushed). The search must
      # still run.
      view
      |> form("form[phx-change='query_change']", query: "Movie A")
      |> render_submit()

      assert render_until(view, "Movie.A.2024.2160p.BluRay") =~ "Movie.A.2024.2160p.BluRay"
    end
  end

  describe "plan flow — targeting → board → approve (UIDR-014)" do
    # Track clicks fire release tracking's off-process artwork download;
    # give it a stubbed CDN and a tmp cache so it lands instead of failing.
    setup {TmdbStubs, :setup_artwork_cache}

    defp stub_selection do
      %MediaCentaur.Acquisition.Targeting.Selection{
        tmdb_id: "246810",
        title: "Sample Show",
        tracked?: false,
        seasons: [
          %MediaCentaur.Acquisition.Targeting.Season{
            season_number: 1,
            episodes:
              for episode <- 1..2 do
                %MediaCentaur.Acquisition.Targeting.Episode{
                  season_number: 1,
                  episode_number: episode,
                  label: "Episode #{episode}",
                  aired?: true,
                  in_library?: false
                }
              end
          }
        ]
      }
    end

    defp stub_plan_tmdb do
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_routes([
        {"/tv/246810/season/1",
         TmdbStubs.season_detail(%{
           "season_number" => 1,
           "episodes" => [
             %{"episode_number" => 1, "name" => "Pilot", "air_date" => "2020-01-01"},
             %{"episode_number" => 2, "name" => "Second", "air_date" => "2020-01-08"}
           ]
         })},
        {"/tv/246810",
         TmdbStubs.tv_detail(%{
           "id" => 246_810,
           "name" => "Sample Show",
           "seasons" => [%{"season_number" => 1, "episode_count" => 2}]
         })}
      ])
    end

    defp stub_plan_prowlarr do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              if query == "Sample Show Season 1" do
                [
                  %{
                    "title" => "Sample.Show.S01.COMPLETE.1080p.WEB-DL",
                    "guid" => "plan-pack",
                    "indexerId" => 1,
                    "seeders" => 30,
                    "indexer" => "indexer-a"
                  }
                ]
              else
                []
              end

            Req.Test.json(conn, results)

          {"POST", "/api/v1/search"} ->
            Req.Test.json(conn, %{"approved" => true})

          _other ->
            Req.Test.json(conn, %{})
        end
      end)
    end

    test "the TV picker introduces the series in the pinned lockup", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")
      render_async(view, 2_000)

      # The identity lives in the cinematic frame's orientation block —
      # the fixture has no logo, so the logotype fallback carries the
      # series name (the poster-thumbnail header was retired with the
      # cinematic-shell re-seat).
      assert has_element?(view, "[data-plan-modal] .detail-orientation h2", "Sample Show")
    end

    test "the TV picker dresses the modal in the series backdrop", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")
      render_async(view, 2_000)

      # tv_detail fixture default backdrop, w1280 on the cinematic shell —
      # the TV path wears the same dress the movie confirm always has.
      assert has_element?(
               view,
               "[data-plan-modal] .modal-page-backdrop img[src='https://image.tmdb.org/t/p/w1280/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg']"
             )
    end

    # The TmdbArtwork cache resolves from disk (not item columns), so the
    # cached-artwork tests seed a real file under a tmp data_dir —
    # GlobalStateSandbox restores the config term afterwards.
    defp seed_cached_backdrop(media_type, tmdb_id) do
      data_dir = Path.join(System.tmp_dir!(), "incoming_artwork_#{System.unique_integer([:positive])}")
      dir = Path.join([data_dir, "images", "tmdb", "#{media_type}-#{tmdb_id}"])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "backdrop.jpg"), :binary.copy("x", 60_000))

      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, :data_dir, data_dir))
      on_exit(fn -> File.rm_rf!(data_dir) end)
    end

    test "the board wears release tracking's cached artwork for the plan's title", %{conn: conn} do
      stub_plan_tmdb()
      seed_cached_backdrop(:movie, 777)

      create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")
      render_async(view, 2_000)

      assert has_element?(
               view,
               "[data-plan-modal] .modal-page-backdrop img[src='/media-images/images/tmdb/movie-777/backdrop.jpg']"
             )
    end

    test "draft rows wear cached artwork instead of the synthetic gradient", %{conn: conn} do
      stub_plan_tmdb()
      seed_cached_backdrop(:movie, 777)

      create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      # Prefix-matched: the assertion is "this row wears the cached artwork",
      # not "at this display width" — the `?w=` hint is a rendering decision
      # the banner is free to retune (MC0028).
      assert has_element?(
               view,
               "#plan-draft-#{plan.id} img[src^='/media-images/images/tmdb/movie-777/backdrop.jpg']"
             )
    end

    test "switching to a different plan clears the previous plan's stale activity line", %{
      conn: conn
    } do
      # Both plans stay planning (no jobs run): the latest search line is
      # the receipts' first line only while a plan is still searching.
      {:ok, plan_a} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})
      {:ok, plan_b} = Plans.create_movie_plan(%{tmdb_id: "778", title: "Other Movie"})

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan_a.id}")

      send(
        view.pid,
        %PlanEvents.SearchActivity{
          plan_id: plan_a.id,
          term: "Sample Movie 2026",
          outcome: :live,
          result_count: 54
        }
      )

      assert render(view) =~ "Searched: Sample Movie 2026 — 54 found"

      render_patch(view, ~p"/downloads?plan=#{plan_b.id}")
      refute render(view) =~ "Sample Movie 2026"
    end

    test "the TV picker's Download creates the plan and leaves the rung and tracking alone",
         %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")
      render_async(view, 2_000)

      # Release tracking is set on the watchlist and nowhere else: a
      # download never moves a rung or creates a tracked title.
      view
      |> element("[phx-click='plan_preset'][phx-value-preset='everything_aired']")
      |> render_click()

      view
      |> element("button[phx-click='plan_create']")
      |> render_click()

      _ = render(view)
      assert [_draft] = Plans.list_drafts()
      assert Watchlist.rung(246_810, :tv_series) == nil
      refute ReleaseTracking.get_item_by_tmdb(246_810, :tv_series)
    end

    test "the picker's Download under auto-select creates an automatic plan, closes and flashes",
         %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv&mode=auto_select_best_release"
        )

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      # A started download lands on Activity, where it shows up, and points
      # the sidebar's Downloads entry there for the next visit.
      assert_patch(view, "/downloads")
      assert_push_event(view, "nav-remember", %{path: "/downloads", url: "/downloads"})
      refute has_element?(view, "#plan-modal[data-state='open']")
      assert render(view) =~ "Finding a release for Sample Show"
      await_supervised_tasks()

      assert [plan] = Plans.list_drafts()
      assert plan.approval_policy == "automatic"
    end

    test "the picker's Download under manual selection creates a review plan and opens its board",
         %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv&mode=manually_select_release"
        )

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      assert [plan] = Plans.list_drafts()
      assert plan.approval_policy == "review"
      assert_patch(view, "/downloads?plan=#{plan.id}")
    end

    test "a link without a mode performs the person's default", %{conn: conn} do
      PlanningMode.set(:auto_select_best_release)
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      assert_patch(view, "/downloads")
      await_supervised_tasks()
      assert [%{approval_policy: "automatic"}] = Plans.list_drafts()
    end

    test "the movie confirm follows the mode too", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_get_movie(550, TmdbStubs.movie_detail(%{"release_date" => "2005-01-01"}))

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/downloads?plan=new&tmdb_id=550&tmdb_type=movie&mode=auto_select_best_release"
        )

      render_async(view, 2_000)
      view |> element("button[phx-click='plan_create']") |> render_click()

      assert_patch(view, "/downloads")
      assert render(view) =~ "Finding a release for Sample Movie"
      await_supervised_tasks()
      assert [%{approval_policy: "automatic", tmdb_type: "movie"}] = Plans.list_drafts()
    end

    test "the picker's Download is a split: the main segment performs the link's mode, the menu names the other",
         %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv&mode=auto_select_best_release"
        )

      render_async(view, 2_000)
      assert has_element?(view, "#plan-download[phx-click='plan_create']", "Download 2 episodes")
      refute has_element?(view, "#plan-download-menu")

      # The picker's actions sit in the frame's foot, the `plan_foot`
      # region pinned at the panel's bottom — never inside the scrolling body.
      assert has_element?(view, "#plan-modal [data-nav-zone='plan_foot'] #plan-download")
      refute has_element?(view, "#plan-modal [data-nav-zone='plan_body'] #plan-download")

      view |> element("#plan-download-toggle") |> render_click()
      assert has_element?(view, "#plan-download-menu[data-nav-zone='plan_menu']")

      assert has_element?(
               view,
               "#plan-download-other[phx-value-mode='manually_select_release']",
               "Manually select release"
             )

      # The menu item performs the other mode: a review plan, its board opening.
      view |> element("#plan-download-other") |> render_click()

      assert [plan] = Plans.list_drafts()
      assert plan.approval_policy == "review"
      assert_patch(view, "/downloads?plan=#{plan.id}")
    end

    test "the picker's menu closes on its close event and starts closed on a new open", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")
      render_async(view, 2_000)

      view |> element("#plan-download-toggle") |> render_click()
      assert has_element?(view, "#plan-download-menu")

      render_click(view, "plan_menu_close", %{})
      refute has_element?(view, "#plan-download-menu")

      view |> element("#plan-download-toggle") |> render_click()
      assert has_element?(view, "#plan-download-menu")

      # The same title under another mode is a new open: the menu starts closed.
      render_patch(
        view,
        ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv&mode=auto_select_best_release"
      )

      render_async(view, 2_000)
      assert has_element?(view, "#plan-download")
      refute has_element?(view, "#plan-download-menu")
    end

    test "with nothing selected the split is inert but stays a nav item", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")
      render_async(view, 2_000)

      view |> element("[phx-click='plan_preset'][phx-value-preset='clear']") |> render_click()

      assert has_element?(
               view,
               "#plan-download[aria-disabled='true'][data-nav-item]",
               "Download 0 episodes"
             )

      view |> element("#plan-download") |> render_click()
      assert Plans.list_drafts() == []
    end

    test "the movie confirm's Download is the same split, its menu the other mode", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_get_movie(550, TmdbStubs.movie_detail(%{"release_date" => "2005-01-01"}))

      {:ok, view, _html} =
        live_async!(
          conn,
          ~p"/downloads?plan=new&tmdb_id=550&tmdb_type=movie&mode=manually_select_release"
        )

      render_async(view, 2_000)
      assert has_element?(view, "#plan-download[phx-click='plan_create']", "Download")

      view |> element("#plan-download-toggle") |> render_click()

      view
      |> element("#plan-download-other[phx-value-mode='auto_select_best_release']")
      |> render_click()

      assert_patch(view, "/downloads")
      await_supervised_tasks()
      assert [%{approval_policy: "automatic", tmdb_type: "movie"}] = Plans.list_drafts()
    end

    test "a mode the link cannot mean opens nothing, plans nothing, and says so", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} =
        live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv&mode=grab_everything")

      html = render_async(view, 2_000)
      refute has_element?(view, "#plan-modal[data-state='open']")
      refute has_element?(view, "button[phx-click='plan_create']")
      assert html =~ "Malformed plan link."
      assert Plans.list_drafts() == []
    end

    test "a plan id that is not one closes the modal instead of crashing the page", %{conn: conn} do
      {:ok, view, html} = live_async!(conn, ~p"/downloads?plan=abc")

      refute has_element?(view, "#plan-modal[data-state='open']")
      assert html =~ "Malformed plan link."
    end

    test "the movie confirm offers Download before release", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_get_movie(550, TmdbStubs.movie_detail(%{"release_date" => "2099-01-01"}))

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=550&tmdb_type=movie")
      render_async(view, 2_000)

      # Download is not gated on the release date; watching for a release
      # is the ladder's job, on the watchlist.
      assert has_element?(view, "button[phx-click='plan_create']", "Download")
    end

    test "the picker's seasons start collapsed and expand on demand", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")
      render_async(view, 2_000)

      # Collapsed by default — the season header renders, the episode rows don't.
      assert has_element?(view, "#plan-season-246810-1-head")
      refute has_element?(view, "#plan-episode-1-1")

      view
      |> element("#plan-season-246810-1-head")
      |> render_click()

      assert has_element?(view, "#plan-episode-1-1")

      view
      |> element("#plan-season-246810-1-head")
      |> render_click()

      refute has_element?(view, "#plan-episode-1-1")
    end

    test "Clear selected empties the picker's selection", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")
      html = render_async(view, 2_000)

      # Opens with the everything-aired default — Clear selected empties it.
      assert html =~ "2 selected"
      assert has_element?(view, "[phx-click='plan_preset'][phx-value-preset='clear']", "Clear selected")

      view
      |> element("[phx-click='plan_preset'][phx-value-preset='clear']")
      |> render_click()

      assert render(view) =~ "0 selected"
    end

    test "the movie confirm stage renders the movie hero artwork", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_get_movie(550, TmdbStubs.movie_detail())

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=550&tmdb_type=movie")
      html = render_async(view, 2_000)

      assert html =~ "Sample Movie"

      # Detail-shaped preview: the backdrop is the full-master hero image
      # (movie_detail fixture backdrop_path). No logo in the fixture, so the
      # title renders as the fallback above it.
      assert has_element?(
               view,
               "[data-plan-modal] img[src='https://image.tmdb.org/t/p/original/hZkgoQYus5dXo3H8T7Uef6DNknx.jpg']"
             )
    end

    test "the movie confirm stage shows identity-confirming facts from TMDB", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_get_movie(550, TmdbStubs.movie_detail())

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=550&tmdb_type=movie")
      html = render_async(view, 2_000)

      # movie_detail fixture: overview, 139min runtime, Drama genre.
      assert html =~ "A sample movie overview."
      assert html =~ "2h 19m"
      assert html =~ "Drama"
    end

    test "the whole door: pick → picker defaults → plan → board → approve → back to Activity", %{
      conn: conn
    } do
      stub_plan_tmdb()
      stub_plan_prowlarr()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=new&tmdb_id=246810&tmdb_type=tv")

      # Targeting stage loads async; default preset = everything aired.
      html = render_async(view, 2_000)
      assert html =~ "Sample Show"
      assert html =~ "2 selected"
      assert html =~ "Download 2 episodes"

      # Seasons start collapsed — episode rows appear only after expanding.
      view
      |> element("#plan-season-246810-1-head")
      |> render_click()

      # Unchecking one unit updates the live count.
      view
      |> element("[phx-click='plan_toggle_unit'][phx-value-season='1'][phx-value-episode='2']")
      |> render_click()

      assert render(view) =~ "1 selected"

      view
      |> element("[phx-click='plan_preset'][phx-value-preset='everything_aired']")
      |> render_click()

      # A live search query survives the picker being open…
      view
      |> form("form[phx-change='query_change']", query: "z")
      |> render_change()

      assert has_element?(view, "#omnibox-release-input[value='z']")

      # Create: the patch carries the plan id; running the enqueued job
      # solves it.
      view
      |> element("button[phx-click='plan_create']")
      |> render_click()

      _ = render(view)
      [draft] = Plans.list_drafts()
      assert_patch(view, "/downloads?plan=#{draft.id}")
      MediaCentaur.JobRuns.run_enqueued_jobs()

      # The board: ready and clean — the verdict says so (no status line),
      # both cells in the pack's line (a capsule), approve enabled.
      html = render(view)
      assert html =~ "Everything you asked for was found."
      assert html =~ "Sample.Show.S01.COMPLETE.1080p.WEB-DL"
      assert html =~ "Season 1 pack"
      assert html =~ "Approve plan"

      # The board's actions sit in the frame's foot (`plan_foot`), pinned at
      # the panel's bottom, so Approve is in reach however long the body is.
      assert has_element?(
               view,
               "#plan-modal [data-nav-zone='plan_foot'] button[phx-click='plan_approve']"
             )

      view
      |> element("button[phx-click='plan_approve']")
      |> render_click()

      # Approval grabs run async (the LV must stay responsive).
      _ = render_async(view, 2_000)
      _ = render(view)

      # Approval closes the modal and lands on Activity. The plan is
      # committed and proceeds on its own; the in-flight row is there to
      # click into for detail, rather than a modal opening over the user.
      {:ok, plan} = Plans.fetch(draft.id)
      assert plan.status == "committed"
      assert_patch(view, "/downloads")

      units = Units.for_pursuit(plan.pursuit_id)
      assert length(units) == 2
    end

    test "the swap picker: find-more live-fills alternatives; choosing reassigns the unit", %{
      conn: conn
    } do
      stub_plan_tmdb()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              case query do
                "Sample Show Season 1" ->
                  [
                    %{
                      "title" => "Sample.Show.S01.COMPLETE.1080p.WEB-DL",
                      "guid" => "ui-pack",
                      "indexerId" => 1,
                      "seeders" => 30,
                      "indexer" => "indexer-a"
                    }
                  ]

                "Sample Show S01E01" ->
                  [
                    %{
                      "title" => "Sample.Show.S01E01.2160p.WEB-DL.x265",
                      "guid" => "ui-uhd",
                      "indexerId" => 1,
                      "seeders" => 8,
                      "indexer" => "indexer-a"
                    }
                  ]

                _other ->
                  []
              end

            Req.Test.json(conn, results)

          {"POST", "/api/v1/search"} ->
            Req.Test.json(conn, %{"approved" => true})

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      [unit | _] = Plans.units_for(plan.id)

      view
      |> element("button[phx-click='plan_show_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      # The search never reached episode terms — the picker starts empty.
      # The current assignment anchors the list, marked as such.
      html = render(view)
      assert html =~ "Nothing else known yet"
      refute html =~ "Sample.Show.S01E01.2160p.WEB-DL.x265"
      assert html =~ "Choose a release"
      assert has_element?(view, "#plan-alternatives-current")
      assert html =~ "Current"

      # The header ✕ closes the picker; Options reopens it.
      view |> element("#plan-alternatives-close") |> render_click()
      refute render(view) =~ "Nothing else known yet"

      view
      |> element("button[phx-click='plan_show_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      view
      |> element("button[phx-click='plan_find_more_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      html = render_async(view, 2_000)
      assert html =~ "Sample.Show.S01E01.2160p.WEB-DL.x265"

      # Exclude lives on the release row's ✕ and Search again at board
      # level — neither belongs inside the picker anymore.
      refute html =~ "Exclude this release"
      refute has_element?(view, "[phx-click='plan_search_again']")

      view
      |> element("input[phx-click='plan_choose_release'][phx-value-guid='ui-uhd']")
      |> render_click()

      html = render(view)

      reloaded = plan.id |> Plans.units_for() |> Enum.find(&(&1.id == unit.id))
      assert reloaded.assigned_guid == "ui-uhd"

      # The narrowing choice left the pack physically containing E01 — the
      # board warns about the duplicate data and offers the resolution.
      assert html =~ "download twice"

      view
      |> element("button[phx-click='plan_swap_release']", "Remove it & re-solve")
      |> render_click()

      MediaCentaur.JobRuns.run_enqueued_jobs()
      html = render(view)
      refute html =~ "download twice"

      units = Plans.units_for(plan.id)
      assert Enum.find(units, &(&1.id == unit.id)).assigned_guid == "ui-uhd"
      assert Enum.find(units, &(&1.id != unit.id)).status == "unfound"
    end

    test "find-more re-fires are no-ops while a search is in flight", %{conn: conn} do
      stub_plan_tmdb()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              if query == "Sample Show Season 1" do
                [
                  %{
                    "title" => "Sample.Show.S01.COMPLETE.1080p.WEB-DL",
                    "guid" => "ui-pack",
                    "indexerId" => 1,
                    "seeders" => 30,
                    "indexer" => "indexer-a"
                  }
                ]
              else
                []
              end

            Req.Test.json(conn, results)

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      [unit | _] = Plans.units_for(plan.id)

      view
      |> element("button[phx-click='plan_show_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      # Re-stub: park the searcher's first indexer request until the test
      # releases it, so the search is provably in flight while we re-fire.
      # The latch lives in the searcher task's process dictionary — its
      # ladder-term requests run sequentially in that one process, so only
      # the first request blocks.
      test_pid = self()

      Req.Test.stub(:prowlarr, fn conn ->
        if !Process.get(:prowlarr_released?) do
          send(test_pid, {:prowlarr_search_blocked, self()})

          receive do
            :proceed -> Process.put(:prowlarr_released?, true)
          end
        end

        Req.Test.json(conn, [])
      end)

      view
      |> element("button[phx-click='plan_find_more_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      assert_receive {:prowlarr_search_blocked, searcher_pid}, 1_000

      # The first click flipped searching?: true, which disables the button —
      # a UI-level re-fire can't even be clicked.
      assert_raise ArgumentError, ~r/disabled/, fn ->
        view
        |> element("button[phx-click='plan_find_more_alternatives'][phx-value-unit-id='#{unit.id}']")
        |> render_click()
      end

      # A raw re-fired event (bypassing the disabled markup) must fall
      # through the `searching?: false` match head and change nothing.
      # This pins the guard's no-crash/no-reset behavior — the single-start
      # property itself is enforced by the match head, which a render-level
      # test cannot distinguish from a benign double-start.
      html = render_click(view, "plan_find_more_alternatives", %{"unit-id" => unit.id})
      assert html =~ "Searching…"

      # Release the parked search; the picker settles back to idle.
      send(searcher_pid, :proceed)

      html = render_async(view, 2_000)
      assert html =~ "Find more"
      refute html =~ "Searching…"
    end

    test "the board narrates the search as progress events land", %{conn: conn} do
      stub_plan_tmdb()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              if query == "Sample Show Season 1" do
                [
                  %{
                    "title" => "Sample.Show.S01.COMPLETE.1080p.WEB-DL",
                    "guid" => "ui-pack",
                    "indexerId" => 1,
                    "seeders" => 30,
                    "indexer" => "indexer-a"
                  }
                ]
              else
                []
              end

            Req.Test.json(conn, results)

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      # Ready board, no progress event yet, panel not seeded (only
      # still-planning boards seed the initial itinerary).
      html = render(view)
      refute html =~ "Planning the search"

      send(view.pid, %PlanEvents.SearchProgress{
        plan_id: plan.id,
        wanted: 2,
        steps: [
          %{scope: :series, kind: :primary, state: :done, term_count: 1, residual_after: 2},
          %{scope: :season, kind: :primary, state: :done, term_count: 2, residual_after: 0},
          %{scope: :episode, kind: :primary, state: :skipped, term_count: nil, residual_after: nil}
        ]
      })

      # On a ready board the step rows are the receipts under *How we
      # searched*, always shown (UIDR-029 as amended 2026-11-06); the
      # headline duty is the verdict's.
      html = render(view)
      assert html =~ "How we searched"
      assert html =~ "not needed — already covered"
      refute html =~ "Everything covered — the deeper searches weren&#39;t needed."

      # A board reload for the SAME plan (Changed event) must not reset
      # the live panel back to the initial itinerary.
      send(view.pid, %PlanEvents.Changed{plan_id: plan.id, status: "ready"})

      html = render(view)
      assert html =~ "not needed — already covered"

      # A status for some other plan must not clobber the open board's panel.
      send(view.pid, %PlanEvents.SearchProgress{
        plan_id: Ecto.UUID.generate(),
        wanted: 9,
        steps: [
          %{scope: :series, kind: :primary, state: :active, term_count: 1, residual_after: nil},
          %{scope: :season, kind: :primary, state: :pending, term_count: nil, residual_after: nil},
          %{scope: :episode, kind: :primary, state: :pending, term_count: nil, residual_after: nil}
        ]
      })

      html = render(view)
      assert html =~ "not needed — already covered"
    end

    test "a draft whose search found nothing says so instead of asking for approval", %{
      conn: conn
    } do
      stub_plan_tmdb()

      # Default Prowlarr stub returns nothing — the board is empty, and
      # the modal offers no Approve, so the card must not promise one.
      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      assert has_element?(view, "#plan-draft-#{plan.id}", "Nothing found")
      refute has_element?(view, "#plan-draft-#{plan.id}", "review and approve")
    end

    test "a draft with releases asks for review and approval", %{conn: conn} do
      stub_plan_tmdb()
      stub_plan_prowlarr()

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      assert has_element?(view, "#plan-draft-#{plan.id}", "review and approve")
      refute has_element?(view, "#plan-draft-#{plan.id}", "Nothing found")
    end

    test "a draft plan resumes from the page and can be discarded", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, plan} =
        Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})

      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      assert has_element?(view, "#plan-draft-#{plan.id}")

      view
      |> element("button#plan-draft-#{plan.id}")
      |> render_click()

      assert_patch(view, "/downloads?plan=#{plan.id}")

      view
      |> element("button[phx-click='plan_discard']")
      |> render_click()

      view
      |> element("button[phx-click='plan_discard']")
      |> render_click()

      _ = render(view)
      assert_patch(view, "/downloads")

      {:ok, discarded} = Plans.fetch(plan.id)
      assert discarded.status == "discarded"
      refute has_element?(view, "#plan-draft-#{plan.id}")
    end

    test "discarding a draft plan takes two clicks, and anything else disarms it", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, plan} =
        Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})

      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      view
      |> element("button#plan-draft-#{plan.id}")
      |> render_click()

      assert_patch(view, "/downloads?plan=#{plan.id}")

      # First click only arms: the control relabels, the plan is untouched
      # (MC0027 tier 2 — no overlay, so nothing can open behind anything).
      html =
        view
        |> element("button[phx-click='plan_discard']")
        |> render_click()

      assert html =~ "Press again to discard"
      {:ok, untouched} = Plans.fetch(plan.id)
      refute untouched.status == "discarded"

      # Any other interaction reads as a change of mind and disarms it.
      html =
        view
        |> element("button[phx-click='plan_search_again']")
        |> render_click()

      refute html =~ "Press again to discard"
      {:ok, kept} = Plans.fetch(plan.id)
      refute kept.status == "discarded"

      # Search again re-solves the plan; the board is back to ready.
      MediaCentaur.JobRuns.run_enqueued_jobs()
      _ = render(view)

      # And a disarmed second click cannot fire: the control is back to
      # arming, so the plan still survives.
      view
      |> element("button[phx-click='plan_discard']")
      |> render_click()

      {:ok, still_there} = Plans.fetch(plan.id)
      refute still_there.status == "discarded"
    end

    test "the TV gap banner states the live verdict with its receipts (UIDR-022)", %{conn: conn} do
      stub_plan_tmdb()

      # Default Prowlarr stub returns nothing — every wanted unit is a gap.
      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")
      html = render(view)

      # The adaptive verdict (UIDR-022): zero raw results, checked live —
      # the banner says what the counts prove, with the receipts beneath.
      assert html =~ "No indexer had anything for these episodes."

      assert html =~
               "5 searches — checked just now."

      # TV recourse is deferred — no escape hatch on aggregate gaps. The
      # button exists on movie boards; a shared banner must not carry it
      # onto TV, where there is no rejected list to show.
      refute has_element?(view, "button[phx-click='plan_show_rejected']")
    end

    test "the gap banner diagnoses rejected results and the override assigns one (UIDR-022)", %{
      conn: conn
    } do
      # A movie board reads its release window from TMDB; the bare stub
      # answers with no dates, so the search diagnosis stands.
      TmdbStubs.setup_tmdb_client()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              case query do
                "Sample Movie 1990" ->
                  [
                    %{
                      "title" => "Another.Picture.1990.1080p.WEB-DL.x264",
                      "guid" => "other-1",
                      "indexerId" => 1,
                      "indexer" => "indexer-a",
                      "seeders" => 5,
                      "size" => 2_000_000_000
                    },
                    %{
                      "title" => "Sample.Movie.1990.1080p.WEB-DL.x264",
                      "guid" => "bait-1",
                      "indexerId" => 1,
                      "indexer" => "indexer-a",
                      "seeders" => 40,
                      "size" => 1_000_000
                    }
                  ]

                _other ->
                  []
              end

            Req.Test.json(conn, results)

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 1990})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")
      html = render(view)

      assert html =~ "2 results came back, but none looked like this movie."
      assert html =~ "Searched “Sample Movie 1990” and “Sample Movie” — checked just now."

      # The escape hatch lists the rejected results with the gate each failed.
      html =
        view
        |> element("button[phx-click='plan_show_rejected']", "Show them anyway")
        |> render_click()

      assert html =~ "Another.Picture.1990.1080p.WEB-DL.x264"
      assert html =~ "match this title"
      assert html =~ "flagged suspicious"
      # The rejected panel carries no corpus-refresh verb.
      refute has_element?(view, "button[phx-click='plan_find_more_alternatives']")

      # Choosing one is the deliberate identity override — it assigns.
      view
      |> element("input[phx-click='plan_choose_rejected'][phx-value-guid='other-1']")
      |> render_click()

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "other-1"

      # The gap is closed; banner and panel are gone.
      html = render(view)
      refute html =~ "came back, but none"
      assert html =~ "Another.Picture.1990.1080p.WEB-DL.x264"
    end

    test "no pursuits renders no empty-state banner — the omnibox is the affordance", %{
      conn: conn
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      refute has_element?(view, "section", "No active pursuits")
      refute has_element?(view, "button", "Search for something to watch")
    end

    test "the board navigates as head / lines / foot regions and its cells are a line's sub-items",
         %{conn: conn} do
      stub_plan_tmdb()
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")
      [unit | _] = Plans.units_for(plan.id)

      assert has_element?(view, "[data-plan-modal][data-nav-overlay='plan']")
      # Nothing was found: the one line is the not-found line, an item of
      # the lines region; the acts (Discard, the watchlist slot) are in the
      # frame's foot.
      assert has_element?(
               view,
               "[data-nav-zone='plan_lines'] [data-plan-line='not_found'][data-nav-item]"
             )

      assert has_element?(view, "[data-nav-zone='plan_foot'] [data-nav-item]")

      # A cell is its line's sub-item, named by its episode through the app
      # tooltip (UIDR-029 as amended 2026-11-06).
      assert has_element?(
               view,
               "[data-plan-line='not_found'] #plan-cell-#{unit.id}[data-nav-sub-item][data-tip]"
             )
    end

    test "a board cell drops its unit from the plan and puts it back", %{conn: conn} do
      stub_plan_tmdb()
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")
      [unit | _] = Plans.units_for(plan.id)

      view |> element("#plan-cell-#{unit.id}") |> render_click()

      assert plan.id |> Plans.units_for() |> Enum.find(&(&1.id == unit.id)) |> Map.fetch!(:status) ==
               "excluded"

      view |> element("#plan-cell-#{unit.id}") |> render_click()

      refute plan.id |> Plans.units_for() |> Enum.find(&(&1.id == unit.id)) |> Map.fetch!(:status) ==
               "excluded"
    end

    test "taking lower quality stores it, follows nothing, re-solves, and can be undone", %{
      conn: conn
    } do
      stub_lower_quality_movie()

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      view
      |> element("button[phx-click='plan_accept_lower_quality']")
      |> render_click()

      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert TitleDownloadParams.get(246_813, :movie).min_quality == "any"

      # Adjusting a quality floor is not a request to follow the film.
      refute ReleaseTracking.get_item_by_tmdb(246_813, :movie)

      html = render(view)
      assert html =~ "Lower quality accepted for this show"

      assert [unit] = Plans.units_for(plan.id)
      assert unit.status == "found"
      assert unit.assigned_guid == "bf-720p"

      view
      |> element("button[phx-click='plan_undo_lower_quality']")
      |> render_click()

      assert TitleDownloadParams.get(246_813, :movie).min_quality == nil
      refute render(view) =~ "Lower quality accepted for this show"
    end

    test "a gapless below-preference plan leads with the lower-quality verdict", %{conn: conn} do
      stub_lower_quality_movie()

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      assert render(view) =~ "nothing at your quality preference"
    end

    test "a planning board offers one-press Stop searching instead of Discard", %{conn: conn} do
      stub_lower_quality_movie()

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      MediaCentaur.JobRuns.run_enqueued_jobs()
      # The struct still says "planning" from before the run, so a
      # stale-struct force diffs to a no-op — refetch first.
      {:ok, ready} = Plans.fetch(plan.id)
      force_attrs(ready, status: "planning")

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      assert has_element?(view, "button[phx-click='plan_stop_searching']")
      refute has_element?(view, "button[phx-click='plan_discard']")

      view
      |> element("button[phx-click='plan_stop_searching']")
      |> render_click()

      {:ok, stopped} = Plans.fetch(plan.id)
      assert stopped.status == "discarded"
    end

    test "a below-floor movie offers the picker instead of a bare gap", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            results =
              if query == "Sample Movie 2005" do
                [
                  %{
                    "title" => "Sample.Movie.2005.720p.WEBRip.x264",
                    "guid" => "bf-720p",
                    "indexerId" => 1,
                    "seeders" => 9,
                    "size" => 1_400_000_000,
                    "indexer" => "indexer-a"
                  },
                  %{
                    "title" => "Sample.Movie.2005.AMZN.WEB-DL.DDP2.0.H.264",
                    "guid" => "bf-unlabeled",
                    "indexerId" => 1,
                    "seeders" => 2,
                    "size" => 1_000_000_000,
                    "indexer" => "indexer-a"
                  }
                ]
              else
                []
              end

            Req.Test.json(conn, results)

          {"POST", "/api/v1/search"} ->
            Req.Test.json(conn, %{"approved" => true})

          _other ->
            Req.Test.json(conn, %{})
        end
      end)

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")
      html = render(view)

      assert html =~ "This movie is available only in lower quality — 2 releases found."
      assert html =~ "Take lower quality"
      assert html =~ "Your quality preference for everything else stays as it is."
      # Below-floor owns the unit — no gap banner world renders.
      refute html =~ "came back, but none"
      refute html =~ "No indexer had anything"

      [unit] = Plans.units_for(plan.id)

      view
      |> element("button[phx-click='plan_show_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "Sample.Movie.2005.720p.WEBRip.x264"
      # Unified release vocabulary (ReleaseFacts): unlabeled quality reads
      # as the muted "Unknown" quality slot.
      assert html =~ "Unknown"
      # No current assignment — the exclude-and-re-solve verb has no target.
      refute html =~ "Exclude this release"

      view
      |> element("input[phx-click='plan_choose_release'][phx-value-guid='bf-720p']")
      |> render_click()

      assert [grabbed] = Plans.units_for(plan.id)
      assert grabbed.status == "found"
      assert grabbed.assigned_guid == "bf-720p"
      assert grabbed.assigned_quality == "720p"

      # The offer row is gone; the chosen release row is the surface now.
      html = render(view)
      refute html =~ "Nothing matching your quality preference"
      assert html =~ "Sample.Movie.2005.720p.WEBRip.x264"
    end

    # --- the empty outcome (spec 2026-09-14) ---------------------------------

    # The board reads a movie's release window only when TMDB is ready —
    # the same gate the board's artwork fetch stands behind.
    defp stub_movie_calendar(us_dates) do
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_get_movie(
        "246813",
        TmdbStubs.movie_detail(%{
          "id" => 246_813,
          "title" => "Sample Movie",
          "release_dates" => %{
            "results" => [
              %{
                "iso_3166_1" => "US",
                "release_dates" =>
                  Enum.map(us_dates, fn {type, date} ->
                    %{"type" => type, "release_date" => "#{date}T00:00:00.000Z"}
                  end)
              }
            ]
          }
        })
      )
    end

    test "an empty movie board reads TMDB's calendar and lists the title on the watchlist", %{
      conn: conn
    } do
      today = Date.utc_today()
      opened = Date.add(today, -20)
      digital = Date.add(today, 30)
      stub_movie_calendar([{3, opened}, {4, digital}])

      # Default Prowlarr stub returns nothing — the movie is a gap.
      {:ok, plan} =
        Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: today.year})

      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")
      html = render(view)

      # The calendar is the diagnosis; the search receipts stay beneath it.
      assert html =~ "In theaters since #{MediaCentaur.Format.month_day(opened)}"
      assert html =~ "digital release #{MediaCentaur.Format.month_day(digital)}"
      refute html =~ "No indexer had anything"
      assert html =~ "checked just now"

      # Nothing to approve, so the footer's primary slot is the bookmark.
      refute has_element?(view, "button[phx-click='plan_approve']")
      assert has_element?(view, "#plan-add-to-watchlist")
      refute has_element?(view, "#plan-on-watchlist")

      view |> element("#plan-add-to-watchlist") |> render_click()

      assert Watchlist.rung(246_813, :movie) == :list
      assert has_element?(view, "#plan-on-watchlist")
      refute has_element?(view, "#plan-add-to-watchlist")

      # Listing fetches the title's artwork off-process.
      await_supervised_tasks()
    end

    test "an unreleased movie says so", %{conn: conn} do
      today = Date.utc_today()
      opens = Date.add(today, 19)
      stub_movie_calendar([{3, opens}])

      {:ok, plan} =
        Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: today.year})

      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      assert render(view) =~ "Not out yet — in theaters from #{MediaCentaur.Format.month_day(opens)}"
    end

    test "a title already on the watchlist opens its empty board with the marker", %{conn: conn} do
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()
      title = Title.new!(%{tmdb_id: 246_813, media_type: :movie, name: "Sample Movie"})
      {:ok, _intent} = ReleaseTracking.set_rung(title, :list, nil)
      await_supervised_tasks()

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      # A payload with no dates leaves the search diagnosis in place.
      assert render(view) =~ "No indexer had anything for this title."
      assert has_element?(view, "#plan-on-watchlist")
      refute has_element?(view, "#plan-add-to-watchlist")
    end

    test "a TMDB failure leaves the search verdict and still offers the watchlist", %{conn: conn} do
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_tmdb_error("/movie/246813", 500)

      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "246813", title: "Sample Movie", year: 2005})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      assert render(view) =~ "No indexer had anything for this title."
      assert has_element?(view, "#plan-add-to-watchlist")
    end

    test "an empty series board offers the watchlist too", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")
      assert has_element?(view, "#plan-add-to-watchlist")

      view |> element("#plan-add-to-watchlist") |> render_click()

      assert Watchlist.rung(246_810, :tv_series) == :list
      assert has_element?(view, "#plan-on-watchlist")
      await_supervised_tasks()
    end

    test "a board with releases offers Approve, not the watchlist", %{conn: conn} do
      stub_plan_tmdb()
      stub_plan_prowlarr()

      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?plan=#{plan.id}")

      assert has_element?(view, "button[phx-click='plan_approve']")
      refute has_element?(view, "#plan-add-to-watchlist")
      refute has_element?(view, "#plan-on-watchlist")
    end
  end

  describe "the release search box (UIDR-014, amended 2026-11-02)" do
    test "the in-input X dismisses the session", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      refute has_element?(view, "#omnibox-release-clear")

      view
      |> form("form[phx-change='query_change']", query: "Sample Show S01E{01-04}")
      |> render_change()

      assert has_element?(view, "#omnibox-release-clear")

      view
      |> element("#omnibox-release-clear")
      |> render_click()

      refute has_element?(view, "#omnibox-release-clear")
    end

    test "an active session survives a fresh mount", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      view
      |> form("form[phx-change='query_change']", query: "Sample Show S01E0{1,2}")
      |> render_change()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")
      assert has_element?(view, "#omnibox-release-input[value='Sample Show S01E0{1,2}']")
    end
  end

  describe "the plan flow from the title detail (UIDR-014)" do
    test "an unowned title's action row carries the Download menu toggle its entry lands on",
         %{conn: conn} do
      # config.js `entryDefaults.detail_actions` names this toggle, so the
      # row enters beside Download rather than on it: a stray SELECT opens
      # a menu instead of starting a download.
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_series_universe_for_targeting()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?title=tv_series-246810")

      assert has_element?(
               view,
               "[data-nav-zone='detail_actions'] #detail-download-toggle[data-nav-item][tabindex='0']"
             )
    end

    test "Download in the title detail on Downloads patches to the new plan's board", %{conn: conn} do
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()
      # The address fetches the series from TMDB, and the targeting fetch
      # behind Download reads its universe: one stub serves both.
      TmdbStubs.stub_series_universe_for_targeting()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?title=tv_series-246810")
      assert has_element?(view, "#detail-modal[data-state='open']", "Sample Show")

      view |> element("#detail-download") |> render_click()

      # The plan is made under the view's own task; awaiting it means the
      # view has handled the result, so the patch is already here.
      render_async(view, 2_000)
      [plan] = Plans.list_drafts()
      assert plan.approval_policy == "review"
      assert_patch(view, "/downloads?plan=#{plan.id}")
      assert has_element?(view, "#plan-modal[data-state='open']")
      refute has_element?(view, "#detail-modal[data-state='open']")
    end

    test "Download in the title detail on Downloads under auto-select lands on Activity", %{conn: conn} do
      PlanningMode.set(:auto_select_best_release)
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_series_universe_for_targeting()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?title=tv_series-246810")

      view |> element("#detail-download") |> render_click()

      # One patch: the modal is gone and Activity is showing, where the
      # download appears; the sidebar's entry points there too.
      assert_patch(view, "/downloads")
      assert_push_event(view, "nav-remember", %{path: "/downloads", url: "/downloads"})
      refute has_element?(view, "#detail-modal[data-state='open']")
      assert render(view) =~ "Finding a release for Sample Show"
      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert [%{approval_policy: "automatic"}] = Plans.list_drafts()
    end
  end

  describe "zone tabs (Activity | History)" do
    # One seeded row per tab so switching provably swaps content:
    # a tracked release (forecast), an active pursuit (Activity), and
    # an exhausted pursuit (History's ledger).
    defp seed_all_zones do
      tracked_with_release(%{name: "Tabbed Forecast Show"})

      MediaCentaur.TestFactory.create_pursuit_with_target(%{
        media_type: :movie,
        title: "Tabbed Active Movie"
      })

      {exhausted_pursuit, _target} =
        MediaCentaur.TestFactory.create_pursuit_with_target(%{
          media_type: :movie,
          title: "Tabbed Landed Movie"
        })

      MediaCentaur.TestFactory.force_state(exhausted_pursuit, "exhausted")

      :ok
    end

    test "a fresh mount lands on Activity, the bare path, with only that zone on the page", %{
      conn: conn
    } do
      seed_all_zones()
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      assert has_element?(view, "[data-nav-zone='zone-tabs'] .zone-tab-active", "Activity")
      assert has_element?(view, "[data-nav-zone='pursuits']")
      refute has_element?(view, "[data-nav-zone='ledger']")
    end

    test "clicking History names the zone in the URL; clicking Activity patches back to the bare path",
         %{conn: conn} do
      seed_all_zones()
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      view
      |> element("[data-nav-zone='zone-tabs'] [phx-value-zone='history']")
      |> render_click()

      assert_patch(view, "/downloads?zone=history")
      assert has_element?(view, "[data-nav-zone='ledger']")
      refute has_element?(view, "[data-nav-zone='pursuits']")

      view
      |> element("[data-nav-zone='zone-tabs'] [phx-value-zone='activity']")
      |> render_click()

      assert_patch(view, "/downloads")
      assert has_element?(view, "[data-nav-zone='pursuits']")
      refute has_element?(view, "[data-nav-zone='ledger']")
    end

    test "?zone=history mounts straight into the open archive", %{conn: conn} do
      seed_all_zones()
      {:ok, view, _html} = live_async!(conn, ~p"/downloads?zone=history")

      assert has_element?(view, "[data-nav-zone='zone-tabs'] .zone-tab-active", "History")
      # The tab IS "View all": filter chips and search render immediately,
      # no disclosure to open, and the default filter shows everything.
      assert has_element?(view, "[data-nav-zone='ledger'] #ledger-filter [aria-pressed='true']", "All")
      assert has_element?(view, "[data-nav-zone='ledger'] input[type='search']")
      assert has_element?(view, "[data-nav-zone='ledger']", "Tabbed Landed Movie")
      refute has_element?(view, "[data-nav-zone='pursuits']")
    end

    test "archive rows speak the quiet vocabulary — sentences only where they inform", %{
      conn: conn
    } do
      for {title, state} <- [
            {"Quiet Landed Movie", "satisfied"},
            {"Quiet Cancelled Movie", "cancelled"},
            {"Loud Failed Movie", "exhausted"}
          ] do
        {pursuit, _target} =
          MediaCentaur.TestFactory.create_pursuit_with_target(%{media_type: :movie, title: title})

        pursuit |> Ecto.Changeset.change(state: state) |> MediaCentaur.Repo.update!()
      end

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?zone=history")

      # One colored outcome word per row plus relative time…
      assert has_element?(view, "[data-nav-zone='ledger']", "Landed")
      assert has_element?(view, "[data-nav-zone='ledger']", "Cancelled")
      assert has_element?(view, "[data-nav-zone='ledger']", "Failed")
      assert has_element?(view, "[data-nav-zone='ledger']", "ago")

      # …no rote sentences where the outcome word already says it…
      refute has_element?(view, "[data-nav-zone='ledger']", "File landed and identity verified.")
      refute has_element?(view, "[data-nav-zone='ledger']", "This download was cancelled.")

      # …but failures keep their diagnostic sentence.
      assert has_element?(view, "[data-nav-zone='ledger']", "Gave up after")
    end

    test "the archive loads a bounded window; Show older reveals the rest", %{conn: conn} do
      page_size = MediaCentaurWeb.DownloadsLive.HistoryLogic.page_size()

      for index <- 1..(page_size + 1) do
        {pursuit, _target} =
          MediaCentaur.TestFactory.create_pursuit_with_target(%{
            media_type: :movie,
            title: "Windowed Movie #{index}"
          })

        MediaCentaur.TestFactory.force_attrs(pursuit,
          state: "satisfied",
          updated_at: DateTime.add(DateTime.utc_now(:second), -index, :hour)
        )
      end

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?zone=history")

      assert has_element?(view, "[data-nav-zone='ledger']", "Windowed Movie 1")
      refute has_element?(view, "[data-nav-zone='ledger']", "Windowed Movie #{page_size + 1}")
      assert has_element?(view, "[phx-click='history_show_older']")

      view |> element("[phx-click='history_show_older']") |> render_click()

      assert has_element?(view, "[data-nav-zone='ledger']", "Windowed Movie #{page_size + 1}")
      refute has_element?(view, "[phx-click='history_show_older']")

      # A new search resets the window — the needle runs over the whole
      # archive in SQL, and the first page of matches comes back.
      view
      |> form("form[phx-change='set_history_search']")
      |> render_change(%{search: "Windowed"})

      assert has_element?(view, "[phx-click='history_show_older']")
      refute has_element?(view, "[data-nav-zone='ledger']", "Windowed Movie #{page_size + 1}")
    end

    test "the archive is sectioned by date landmarks", %{conn: conn} do
      for {title, days_ago} <- [{"Fresh Landed Movie", 0}, {"Old Landed Movie", 40}] do
        {pursuit, _target} =
          MediaCentaur.TestFactory.create_pursuit_with_target(%{media_type: :movie, title: title})

        MediaCentaur.TestFactory.force_attrs(pursuit,
          state: "satisfied",
          updated_at: DateTime.add(DateTime.utc_now(:second), -days_ago, :day)
        )
      end

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?zone=history")

      month_label =
        Calendar.strftime(DateTime.add(DateTime.utc_now(), -40, :day), "%B %Y")

      # Two entries total: too sparse for any time scope, so the
      # adaptive window shows the whole page — both sections, no
      # pointless button.
      assert has_element?(view, "[data-nav-zone='ledger'] h3", "Today")
      assert has_element?(view, "[data-nav-zone='ledger'] h3", month_label)
      refute has_element?(view, "[phx-click='history_show_older']")
    end

    test "a busy week is the first window; Show older reaches the archive", %{conn: conn} do
      seeds =
        for index <- 1..5, do: {"Recent Week Movie #{index}", index}

      for {title, days_ago} <- seeds ++ [{"Beyond Week Movie", 45}] do
        {pursuit, _target} =
          MediaCentaur.TestFactory.create_pursuit_with_target(%{media_type: :movie, title: title})

        MediaCentaur.TestFactory.force_attrs(pursuit,
          state: "satisfied",
          updated_at: DateTime.add(DateTime.utc_now(:second), -days_ago, :day)
        )
      end

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?zone=history")

      assert has_element?(view, "[data-nav-zone='ledger']", "Recent Week Movie 1")
      refute has_element?(view, "[data-nav-zone='ledger']", "Beyond Week Movie")
      assert has_element?(view, "[phx-click='history_show_older']")

      view |> element("[phx-click='history_show_older']") |> render_click()

      assert has_element?(view, "[data-nav-zone='ledger']", "Beyond Week Movie")
      refute has_element?(view, "[phx-click='history_show_older']")
    end

    test "a sparse week widens to the month before offering Show older", %{conn: conn} do
      seeds =
        [{"Lone Week Movie", 2}] ++
          for(index <- 1..4, do: {"Month Movie #{index}", 10 + index}) ++
          [{"Quarter Movie", 60}]

      for {title, days_ago} <- seeds do
        {pursuit, _target} =
          MediaCentaur.TestFactory.create_pursuit_with_target(%{media_type: :movie, title: title})

        MediaCentaur.TestFactory.force_attrs(pursuit,
          state: "satisfied",
          updated_at: DateTime.add(DateTime.utc_now(:second), -days_ago, :day)
        )
      end

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?zone=history")

      # One entry this week is too sparse — the window widens to the
      # month (5 entries), deferring only the quarter-old row.
      assert has_element?(view, "[data-nav-zone='ledger']", "Lone Week Movie")
      assert has_element?(view, "[data-nav-zone='ledger']", "Month Movie 4")
      refute has_element?(view, "[data-nav-zone='ledger']", "Quarter Movie")
      assert has_element?(view, "[phx-click='history_show_older']")

      view |> element("[phx-click='history_show_older']") |> render_click()

      assert has_element?(view, "[data-nav-zone='ledger']", "Quarter Movie")
    end

    test "an active search recedes the tab bar and the zone content; clearing restores them", %{
      conn: conn
    } do
      seed_all_zones()
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      assert has_element?(view, "[data-nav-zone='zone-tabs']")
      assert has_element?(view, "[data-nav-zone='pursuits']")

      view
      |> form("form[phx-change='query_change']", query: "Sample Show S01E01")
      |> render_change()

      refute has_element?(view, "[data-nav-zone='zone-tabs']")
      refute has_element?(view, "[data-nav-zone='pursuits']")

      render_click(view, "clear_search", %{})

      assert has_element?(view, "[data-nav-zone='zone-tabs']")
      assert has_element?(view, "[data-nav-zone='pursuits']")
    end

    test "empty Activity and History tabs say so instead of rendering a void", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")
      assert has_element?(view, "[data-component='zone-empty']", "Nothing in flight")

      # History has no separate zone-empty line — the always-open archive
      # carries its own honest per-filter empty state.
      {:ok, view, _html} = live_async!(conn, ~p"/downloads?zone=history")
      assert has_element?(view, "section[data-nav-zone='ledger']", "No downloads have ended yet.")
    end

    test "plan-modal patches keep the page's bare path — closing a draft lands back on Activity", %{
      conn: conn
    } do
      stub_plan_tmdb()
      {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      view
      |> element("#plan-draft-#{plan.id}")
      |> render_click()

      assert_patch(view, "/downloads?plan=#{plan.id}")

      render_click(view, "close_plan", %{})
      assert_patch(view, "/downloads")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] .zone-tab-active", "Activity")
    end

    test "without Prowlarr there is no tab bar — a zone param conjures nothing", %{conn: conn} do
      Capabilities.clear_test_result(:prowlarr)

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?zone=history")

      refute has_element?(view, "[data-nav-zone='zone-tabs']")
      refute has_element?(view, "[data-nav-zone='ledger']")
      assert has_element?(view, "#downloads-empty")
    end
  end

  describe "submit_search and grab_selected" do
    test "renders results, lets user select, and submits a grab", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      # Allow the LiveView (and tasks it spawns via $callers) to use the stub.
      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Movie.A.2024.2160p.BluRay",
                "guid" => "guid-a",
                "indexerId" => 1,
                "seeders" => 50,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/release" ->
            Req.Test.json(conn, %{"approved" => true})

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> form("form[phx-change='query_change']", query: "Movie A")
      |> render_submit()

      html = render_until(view, "Movie.A.2024.2160p.BluRay")
      # Default selection should be applied — Grab button shows count of 1
      assert html =~ "Grab 1 selected"

      # Submit the grab
      view
      |> element("button[phx-click='grab_selected']")
      |> render_click()

      html = render_until(view, "1 grab(s) submitted")
      assert html =~ "1 grab(s) submitted"
    end

    test "brace-expanded batch grab collapses into ONE composite pursuit (ADR-055)", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn ->
        # Grabs POST to /api/v1/search too (the Prowlarr grab gotcha) —
        # discriminate searches from grabs by method.
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)

            Req.Test.json(conn, [
              %{
                "title" => "#{query}.1080p.WEB-DL",
                "guid" => "guid-#{query}",
                "indexerId" => 1,
                "seeders" => 10,
                "indexer" => "indexer-a"
              }
            ])

          {"POST", "/api/v1/search"} ->
            Req.Test.json(conn, %{"approved" => true})

          {_, "/api/v1/release"} ->
            Req.Test.json(conn, %{"approved" => true})

          {_, "/api/v1/queue"} ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> form("form[phx-change='query_change']", query: "Sample Show S01E{01-02}")
      |> render_submit()

      html = render_until(view, "Grab 2 selected")
      assert html =~ "Grab 2 selected"

      view
      |> element("button[phx-click='grab_selected']")
      |> render_click()

      render_until(view, "2 grab(s) submitted")
      # Each pick is recorded as a grabbing target; its grab runs in a job.
      MediaCentaur.JobRuns.run_enqueued_jobs()

      # One composite pursuit holding both expanded terms as units, each
      # with its own acquired target.
      [pursuit] = MediaCentaur.Repo.all(MediaCentaur.Acquisition.Pursuits.Pursuit)
      assert pursuit.manual_query == "Sample Show S01E{01-02}"

      units = Units.for_pursuit(pursuit.id)

      assert units |> Enum.map(& &1.query) |> Enum.sort() == [
               "Sample Show S01E01",
               "Sample Show S01E02"
             ]

      for unit <- units do
        assert %Target{status: "acquired"} = MediaCentaur.Repo.get(Target, unit.current_target_id)
      end
    end
  end

  describe "cancel download" do
    setup do
      Req.Test.stub(:qbittorrent, fn conn -> Req.Test.json(conn, []) end)

      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        Map.merge(config, %{
          download_client_type: "qbittorrent",
          download_client_url: "http://qbit.test",
          download_client_username: "alice",
          download_client_password: Secret.wrap("s3cret")
        })
      )

      :ok
    end

    alias MediaCentaur.Downloads.QueueItem

    test "the second click calls qBittorrent delete and clears the row", %{conn: conn} do
      delete_counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"POST", "/api/v2/torrents/delete"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert body == "hashes=aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111&deleteFiles=true"
            :counters.add(delete_counter, 1, 1)
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      # Seed the queue via the same PubSub broadcast QueueMonitor emits.
      send(
        view.pid,
        {:queue_state,
         %MediaCentaur.Downloads.QueueState{
           items: [
             %QueueItem{
               id: "aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111",
               title: "Movie.Test.2024",
               state: :downloading,
               status: "downloading",
               download_client: "qBittorrent",
               size: 100,
               size_left: 50,
               progress: 50.0,
               timeleft: "2m"
             }
           ]
         }}
      )

      html = render(view)
      assert html =~ "Movie.Test.2024"
      assert has_element?(view, "[phx-click='cancel_download']")

      # First click only arms the control — no overlay opens, and nothing
      # has been deleted yet (MC0027 tier 2).
      html =
        view
        |> element("button[phx-click='cancel_download']")
        |> render_click()

      assert html =~ "Press again to cancel"
      assert :counters.get(delete_counter, 1) == 0

      # Second click fires the qBittorrent delete and optimistically drops the row.
      html =
        view
        |> element("button[phx-click='cancel_download']")
        |> render_click()

      assert :counters.get(delete_counter, 1) == 1
      refute has_element?(view, "[phx-value-id='aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111']")
      refute html =~ "Press again to cancel"
    end

    test "ghost row from a stale snapshot does not reappear after cancel", %{conn: conn} do
      # Regression: the LiveView used to overwrite active_queue on every
      # snapshot. If qBittorrent's DELETE took >1 polling cycle to
      # propagate, the next snapshot brought the cancelled row back —
      # the user saw "they just sit there".
      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"POST", "/api/v2/torrents/delete"} ->
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      stale_item = %QueueItem{
        id: "abcd1234abcd1234abcd1234abcd1234abcd1234",
        title: "Ghost.Movie.2024",
        state: :downloading,
        status: "downloading",
        download_client: "qBittorrent",
        size: 100,
        size_left: 50,
        progress: 50.0,
        timeleft: "2m"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [stale_item]}})
      assert has_element?(view, "[phx-value-id='abcd1234abcd1234abcd1234abcd1234abcd1234']")

      view |> element("button[phx-click='cancel_download']") |> render_click()
      view |> element("button[phx-click='cancel_download']") |> render_click()

      # Simulate the next poll arriving before qBittorrent has propagated
      # the deletion — the same item shows up in the snapshot. The LiveView
      # must keep it hidden during the cancel grace window.
      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [stale_item]}})

      # Use the row's phx-value-id rather than the title — the title also
      # appears in the post-cancel flash, which would mask a real failure.
      refute has_element?(view, "[phx-value-id='abcd1234abcd1234abcd1234abcd1234abcd1234']")
    end

    test "another interaction disarms the cancel, and a disarmed click cannot delete",
         %{conn: conn} do
      delete_counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"POST", "/api/v2/torrents/delete"} ->
            :counters.add(delete_counter, 1, 1)
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      send(
        view.pid,
        {:queue_state,
         %MediaCentaur.Downloads.QueueState{
           items: [
             %QueueItem{
               id: "bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222",
               title: "Show.S01E01",
               state: :downloading,
               status: "downloading",
               download_client: "qBittorrent",
               size: 100,
               size_left: 50,
               progress: 50.0,
               timeleft: "2m"
             }
           ]
         }}
      )

      assert render(view) =~ "Show.S01E01"

      html =
        view
        |> element("button[phx-click='cancel_download']")
        |> render_click()

      assert html =~ "Press again to cancel"

      # Touching anything else reads as a change of mind and disarms it.
      html =
        view
        |> element("a[phx-click='switch_zone'][phx-value-zone='activity']")
        |> render_click()

      refute html =~ "Press again to cancel"

      # So the next click on the control arms again rather than firing —
      # the torrent is still there.
      view
      |> element("button[phx-click='cancel_download']")
      |> render_click()

      assert :counters.get(delete_counter, 1) == 0
    end

    test "orphan downloads list keys rows by id and survives mid-list cancel", %{conn: conn} do
      # Regression: Phoenix's positional comprehension diff causes the row
      # at the cancelled position to morph in place into the *next* item's
      # data and the bottom row to disappear when rows lack stable ids.
      # The orphan ("Other jobs") section gives each row its own
      # `id="orphan-{hash}"` so morphdom moves nodes by id even without
      # `phx-update="stream"`.
      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          # IndexerHealth snapshot (UIDR-016): an empty roster classifies as
          # :unconfigured — not blind — so corpus recording behaves as before.
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"POST", "/api/v2/torrents/delete"} ->
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      items =
        for {hash, title} <- [
              {"aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111", "Movie.A.2024"},
              {"bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222", "Movie.B.2024"},
              {"hash-c", "Movie.C.2024"}
            ] do
          %QueueItem{
            id: hash,
            title: title,
            state: :downloading,
            status: "downloading",
            download_client: "qBittorrent",
            size: 100,
            size_left: 50,
            progress: 50.0,
            timeleft: "2m"
          }
        end

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: items}})

      html = render(view)
      assert html =~ "Other jobs"
      assert html =~ ~s|id="orphan-aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111"|
      assert html =~ ~s|id="orphan-bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222"|
      assert html =~ ~s|id="orphan-hash-c"|

      # The arm and the fire are the same button, so both clicks target it
      # by the row's id.
      view
      |> element("button[phx-value-id='bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222']")
      |> render_click()

      html =
        view
        |> element("button[phx-value-id='bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222']")
        |> render_click()

      # The middle row's id is gone, and the surviving rows keep their ids
      # so morphdom can match them by id rather than morphing positionally.
      assert html =~ ~s|id="orphan-aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111"|
      refute html =~ ~s|id="orphan-bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222"|
      assert html =~ ~s|id="orphan-hash-c"|
    end
  end

  describe "retry_search (per-group)" do
    test "a single timed-out search becomes retryable; retry resolves to results",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      Req.Test.allow(:prowlarr, self(), view.pid)

      # First search — every Prowlarr call fails with a transport timeout.
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      view
      |> form("form[phx-change='query_change']", query: "Movie A")
      |> render_submit()

      render_until(view, "Prowlarr timed out")
      # Retry affordance is present alongside the timeout message
      assert has_element?(view, "[phx-click='retry_search']")
      assert has_element?(view, "[phx-value-term='Movie A']")

      # Now succeed on retry
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Movie.A.2024.1080p",
                "guid" => "guid-a",
                "indexerId" => 1,
                "seeders" => 12,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> element("button[phx-click='retry_search'][phx-value-term='Movie A']")
      |> render_click()

      html = render_until(view, "Movie.A.2024.1080p")
      refute html =~ "Prowlarr timed out"
    end
  end

  describe "retry_all_timeouts (footer button)" do
    test "appears only after every search completes and at least one timed out",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      view
      |> form("form[phx-change='query_change']", query: "Sample Show S01E{01,02}")
      |> render_submit()

      render_until(view, "Retry 2 timeouts")
      assert has_element?(view, "[phx-click='retry_all_timeouts']")

      # Switch the stub to succeed, then bulk-retry
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Sample.Show.Episode.1080p",
                "guid" => "guid-#{System.unique_integer([:positive])}",
                "indexerId" => 1,
                "seeders" => 8,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> element("button[phx-click='retry_all_timeouts']")
      |> render_click()

      html = render_until(view, "Sample.Show.Episode.1080p")
      refute html =~ "Prowlarr timed out"
      refute html =~ "Retry 2 timeouts"
    end

    test "does not appear when no searches timed out", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/search" ->
            Req.Test.json(conn, [
              %{
                "title" => "Healthy.Result.1080p",
                "guid" => "g",
                "indexerId" => 1,
                "seeders" => 5,
                "indexer" => "indexer-a"
              }
            ])

          "/api/v1/queue" ->
            Req.Test.json(conn, [])
        end
      end)

      view
      |> form("form[phx-change='query_change']", query: "Healthy")
      |> render_submit()

      _ = render_until(view, "Healthy.Result.1080p")
      refute has_element?(view, "button[phx-click='retry_all_timeouts']")
    end
  end

  describe "debounce on acquisition PubSub events" do
    test "five rapid grab-event broadcasts trigger only one activity reload after the debounce window",
         %{conn: conn} do
      # Regression guard: TargetEvents and related events must be debounced
      # (500ms) rather than calling load_activity on every message. Coalescing
      # is pinned by `LiveHelpers.debounce/4`'s tests; `render/1` is a sync
      # round trip, so the burst has been handled when it returns.
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      for _ <- 1..5 do
        send(view.pid, %TargetEvents.Picked{target: %Target{}})
      end

      assert render(view) =~ "Downloads"
    end
  end

  describe "search session persistence" do
    test "search query and results persist across navigation", %{conn: conn} do
      stub_prowlarr_with([sample_release()])

      {:ok, view, _html} = live_async!(conn, "/downloads")

      view
      |> form("form[phx-change='query_change']", %{"query" => "Sample Show"})
      |> render_submit()

      # The Prowlarr search results arrive asynchronously ({:search_result, …})
      # and re-render the group — poll until they land.
      html = render_until(view, "Sample.Show.S01E01")
      assert html =~ "Sample Show"
      assert html =~ "Sample.Show.S01E01"

      {:ok, _other_view, _other_html} = live_async!(conn, "/")

      {:ok, view2, _html2} = live_async!(conn, "/downloads")
      html2 = render_after_async_load(view2)

      assert html2 =~ "Sample Show"
      assert html2 =~ "Sample.Show.S01E01"
    end

    test "user-changed selection persists across navigation", %{conn: conn} do
      stub_prowlarr_with([
        sample_release(guid: "guid-1", title: "Sample.Show.S01E01.720p.WEB-DL.mkv"),
        sample_release(guid: "guid-2", title: "Sample.Show.S01E01.1080p.WEB-DL.mkv")
      ])

      {:ok, view, _html} = live_async!(conn, "/downloads")

      Req.Test.allow(:prowlarr, self(), view.pid)

      view
      |> form("form[phx-change='query_change']", %{"query" => "Sample Show"})
      |> render_submit()

      _ = render_until(view, "Sample.Show.S01E01")

      # Override the auto-default selection with a user-driven choice.
      SearchSession.set_selection("Sample Show", "guid-2")

      session_before = SearchSession.current()
      assert session_before.selections == %{"Sample Show" => "guid-2"}

      {:ok, _other_view, _other_html} = live_async!(conn, "/")
      {:ok, _view2, _html2} = live_async!(conn, "/downloads")

      session_after = SearchSession.current()
      assert session_after.selections == %{"Sample Show" => "guid-2"}
    end

    test "the subtle Clear search affordance dismisses the session", %{conn: conn} do
      stub_prowlarr_with([
        sample_release(guid: "guid-1", title: "Sample.Show.S01E01.1080p.WEB-DL.mkv")
      ])

      {:ok, view, _html} = live_async!(conn, "/downloads")
      Req.Test.allow(:prowlarr, self(), view.pid)

      view
      |> form("form[phx-change='query_change']", %{"query" => "Sample Show"})
      |> render_submit()

      html = render_until(view, "Sample.Show.S01E01")
      assert html =~ "Clear search"
      refute SearchSession.current().groups == []

      render_click(element(view, "button", "Clear search"))

      assert SearchSession.current().groups == []
    end

    test "an in-flight search survives the LiveView: its results land after the LiveView is stopped", %{
      conn: conn
    } do
      # Searches block until this test releases them; the IndexerHealth
      # snapshot endpoints stay responsive so mount's health async
      # (UIDR-016) doesn't eat the render_async budget — this test is about
      # search-session lifecycle.
      test_pid = self()

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/indexer" ->
            Req.Test.json(conn, [%{"id" => 1, "name" => "Indexer A", "enable" => true}])

          "/api/v1/indexerstatus" ->
            Req.Test.json(conn, [])

          _search ->
            send(test_pid, {:search_blocked, self()})

            receive do
              :release -> Req.Test.json(conn, [])
            end
        end
      end)

      {:ok, view, _html} = live_async!(conn, "/downloads")

      view
      |> form("form[phx-change='query_change']", %{"query" => "Pending Show"})
      |> render_submit()

      session_before = await_session_groups(:loading)
      assert Enum.all?(session_before.groups, fn group -> group.status == :loading end)

      GenServer.stop(view.pid, :normal)

      # The searches are the session's own: the LiveView going away changes
      # nothing for them. Release them and the outcomes land.
      release_blocked_searches()
      session_after = await_session_groups(:ready)
      assert Enum.all?(session_after.groups, fn group -> group.status == :ready end)

      {:ok, view2, _html2} = live_async!(conn, "/downloads")
      assert render_after_async_load(view2) =~ "No results"

      await_supervised_tasks()
    end
  end

  defp release_blocked_searches do
    receive do
      {:search_blocked, pid} ->
        send(pid, :release)
        release_blocked_searches()
    after
      0 -> :ok
    end
  end

  describe "live updates from queue monitor" do
    # The active queue is now driven by QueueMonitor's PubSub broadcast
    # rather than per-LV polling. The LV must consume {:queue_state, %QueueState{items: items}}
    # and re-render the queue zone without making its own download-client
    # call. Without this contract the page would silently regress to stale
    # data after the polling timer was removed.

    alias MediaCentaur.Downloads.QueueItem
    alias MediaCentaur.Downloads.QueueMonitor

    test "queue_snapshot broadcast paints the active queue",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      item = %QueueItem{
        id: "hash-snapshot",
        title: "Snapshot Movie 2026",
        state: :downloading,
        status: "downloading",
        download_client: "qBittorrent",
        size: 100,
        size_left: 50,
        progress: 50.0,
        timeleft: "2m"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [item]}})

      assert render(view) =~ "Snapshot Movie 2026"
    end

    test "queue_snapshot with completed items filters them out",
         %{conn: conn} do
      # QueueMonitor pre-filters completed items, but the LV defends in
      # depth — a stale snapshot from cache or a future driver that emits
      # completed entries must not surface seeded torrents on /downloads.
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      done = %QueueItem{id: "h1", title: "Already Done Movie", state: :completed}
      live_item = %QueueItem{id: "h2", title: "Still Downloading Movie", state: :downloading}

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [done, live_item]}})

      html = render(view)
      refute html =~ "Already Done Movie"
      assert html =~ "Still Downloading Movie"
    end

    test "empty queue_snapshot transitions to the empty state",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      seed = %QueueItem{id: "h3", title: "Soon To Vanish", state: :downloading}
      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [seed]}})
      assert render(view) =~ "Soon To Vanish"

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: []}})

      html = render(view)
      refute html =~ "Soon To Vanish"
      refute html =~ "Other jobs"
    end

    test "capabilities_changed pings QueueMonitor for an immediate poll",
         %{conn: conn} do
      # Without this, a user who just configured their download client would
      # wait up to 30s (QueueMonitor's idle cadence) before the queue
      # populated. Ping QueueMonitor when the LV learns capabilities changed
      # so the queue surfaces within one round-trip.
      test_pid = self()

      Req.Test.stub(:qbittorrent, fn conn ->
        send(test_pid, :qbit_called)
        Req.Test.json(conn, [])
      end)

      monitor = start_supervised!(QueueMonitor)
      Req.Test.allow(:qbittorrent, self(), monitor)

      {:ok, view, _html} = live_async!(conn, ~p"/downloads")

      # Two polls precede the one under test: init's, and the one mount's
      # subscriber registration triggers. A call lands behind both in the
      # monitor's mailbox; once it returns, discard their stub calls so the
      # assertion below can only observe the post-:capabilities_changed poll.
      _ = QueueMonitor.state()
      flush_qbit_calls()

      send(view.pid, :capabilities_changed)

      assert_receive :qbit_called, 1_000

      # Let that poll finish before this process — and the stub allowance
      # that dies with it — goes away; an in-flight sync would crash the
      # monitor on the stub lookup.
      _ = QueueMonitor.state()
    end

    defp flush_qbit_calls do
      receive do
        :qbit_called -> flush_qbit_calls()
      after
        0 -> :ok
      end
    end
  end

  describe "pursuits paired with their live downloads" do
    alias MediaCentaur.Downloads.QueueItem

    defp pursuit_with_acquired_target(title, release_title) do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "tmdb-#{:erlang.phash2(title)}",
          tmdb_type: "movie",
          title: title,
          origin: "auto",
          release_title: release_title,
          status: "acquired"
        })

      pursuit
    end

    test "a matched queue item renders as a download strip under the right pursuit card",
         %{conn: conn} do
      pursuit = pursuit_with_acquired_target("Sample Movie 2010", "Sample.Movie.2010.1080p.WEB-DL")

      {:ok, view, _html} = live_async!(conn, "/downloads")

      matching = %QueueItem{
        id: "hash-paired",
        title: "sample movie 2010 1080p web dl",
        state: :downloading,
        status: "downloading",
        download_client: "qBittorrent",
        progress: 0.5,
        timeleft: "10m"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [matching]}})

      # Await the async pursuit-rows load deterministically rather than
      # relying on render timing (ADR-049: tests drive async to completion).
      html = render_until(view, ~s|data-pursuit-id="#{pursuit.id}"|)
      # The card carries the pursuit id; the cancel button inside its footer
      # carries the queue item id — co-located in the rendered DOM, which is
      # exactly the pairing this redesign delivers.
      assert html =~ ~s|data-pursuit-id="#{pursuit.id}"|
      assert html =~ ~s|phx-value-id="hash-paired"|
      assert html =~ "ETA 10m"
      # Matched items don't surface in the "Other jobs" section.
      refute html =~ "Other jobs"
    end

    test "a matched usenet job in post-processing draws its phase, not a text dump", %{conn: conn} do
      pursuit = pursuit_with_acquired_target("Sample Movie 2010", "Sample.Movie.2010.1080p.WEB-DL")

      {:ok, view, _html} = live_async!(conn, "/downloads")

      unpacking = %QueueItem{
        id: "nzo-unpacking",
        title: "sample movie 2010 1080p web dl",
        state: :extracting,
        status: "Extracting",
        protocol: :usenet,
        download_client: "SABnzbd",
        stage_line: "Unpacking: 45%"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [unpacking]}})

      html = render_until(view, ~s|data-pursuit-id="#{pursuit.id}"|)
      assert html =~ ~s|data-step="unpack" data-step-state="underway"|
      assert html =~ "Unpacking"
      assert html =~ "45%"
      refute html =~ "Other jobs"
    end

    test "an unmatched queue item appears under 'Other jobs', and the pursuit shows its no-match hint",
         %{conn: conn} do
      _pursuit = pursuit_with_acquired_target("Sample Movie 2010", "Sample.Movie.2010.1080p.WEB-DL")

      {:ok, view, _html} = live_async!(conn, "/downloads")

      unrelated = %QueueItem{
        id: "hash-orphan",
        title: "Totally.Different.Movie.2024",
        state: :downloading,
        status: "downloading",
        download_client: "qBittorrent"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [unrelated]}})

      html = render(view)
      assert html =~ "Other jobs"
      assert html =~ ~s|id="orphan-hash-orphan"|
      # The pursuit card surfaces `PursuitStatus.derive`'s `CurrentAction` as
      # its status line when no torrent is matched. This pursuit was grabbed
      # and the client has never shown it, so the card says so — it must not
      # claim the download finished just because the queue doesn't hold it.
      assert html =~ "Grabbed"
      refute html =~ "Finished"
    end

    test "an unmatched job under Other jobs is drawn by the strip — phase word as text, no badge",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/downloads")

      fetching = %QueueItem{
        id: "nzo-orphan-fetch",
        title: "Fetching NZB…",
        state: :fetching_nzb,
        status: "Grabbing",
        protocol: :usenet,
        download_client: "SABnzbd"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [fetching]}})

      html = render(view)
      assert html =~ "Other jobs"
      assert html =~ ~s|id="orphan-nzo-orphan-fetch"|
      assert html =~ ~s|data-step="fetch" data-step-state="underway"|
      assert html =~ "progress-indeterminate"
      refute html =~ ~r/class="[^"]*badge[^"]*"[^>]*>\s*Fetching NZB/
      refute html =~ "0:00:00"
    end

    test "TV pursuits render an SxxExx suffix in the card title", %{conn: conn} do
      {_pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "tv-1001",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 3,
          origin: "auto",
          status: "seeking"
        })

      {:ok, view, _html} = live_async!(conn, "/downloads")

      assert render_after_async_load(view) =~ "Sample Show S01E03"
    end
  end

  describe "live updates from grab lifecycle" do
    # The activity zone shows recent grabs and their state. PubSub events
    # from acquisition coalesce through a 500ms debounce so a season-grab
    # cascade (one event per episode) becomes a single :reload_history
    # tick — without coalescing the page would re-query the History zone
    # five times in quick succession for the same end state.

    test "five rapid grab_failed events coalesce into one reload",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/downloads")

      for _ <- 1..5 do
        send(view.pid, {:target_failed, %{id: Ecto.UUID.generate(), reason: "boom"}})
      end

      # No crash, page still renders History zone (`render/1` is a sync round trip).
      assert render(view) =~ "Downloads"
    end

    test "grab_submitted broadcast triggers a debounced reload without crashing",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/downloads")

      send(view.pid, {:target_picked, %{id: Ecto.UUID.generate()}})
      send(view.pid, {:target_armed, %{id: Ecto.UUID.generate()}})
      send(view.pid, {:target_snoozed, %{id: Ecto.UUID.generate()}})

      assert render(view) =~ "Downloads"
    end
  end

  # Polls the out-of-band search session (a GenServer updated asynchronously
  # by its own searches' outcomes)
  # until every group reaches `status` and at least one group exists. The
  # non-empty guard matters: `Enum.all?([], …)` is vacuously true, so without
  # it a poll would pass before the groups were even created. Deterministic
  # stand-in for a settle sleep; returns the session.
  defp await_session_groups(status, timeout \\ 1_000) do
    eventually(
      fn ->
        session = SearchSession.current()
        session.groups != [] and Enum.all?(session.groups, &(&1.status == status)) and session
      end,
      timeout: timeout,
      message: fn ->
        "search-session groups never all reached #{inspect(status)}; " <>
          "got #{inspect(Enum.map(SearchSession.current().groups, & &1.status))}"
      end
    )
  end

  # The ids of every element matching `selector`, in document order.
  # ---------------------------------------------------------------------------
  # The title detail on this page: a tracked title opened by its address
  # (`?title=`), the host resolving its snapshot from the ladder.
  # ---------------------------------------------------------------------------

  defp tracked_with_release(attrs, release_attrs \\ %{}) do
    item =
      create_tracking_item(
        Map.merge(%{tmdb_id: :rand.uniform(900_000), media_type: :tv_series, name: "Sample Show"}, attrs)
      )

    release =
      create_tracking_release(
        Map.merge(
          %{
            item_id: item.id,
            season_number: 1,
            episode_number: 1,
            air_date: Date.add(Date.utc_today(), 5),
            released: false
          },
          release_attrs
        )
      )

    {item, release}
  end

  describe "title modal" do
    test "a tracked title's address opens the modal from the ladder; close_title patches away", %{
      conn: conn
    } do
      {item, _release} = tracked_with_release(%{name: "Detail Show"})

      {:ok, view, _html} = live_async!(conn, "/downloads?title=tv_series-#{item.tmdb_id}")

      assert has_element?(view, "#detail-modal[data-state=open]")
      opened = render(view)
      assert opened =~ "Detail Show"
      refute opened =~ "Stop tracking"
      assert has_element?(view, "#detail-tracking-controls[data-rung='grab']")
      assert has_element?(view, "#detail-release-dates")

      render_hook(view, "close_title", %{})
      assert_patch(view, "/downloads")
      assert has_element?(view, "#detail-modal[data-state=closed]")
    end

    test "the modal shows a friend's act on a tracked title — resolved by identity, not by the page",
         %{conn: conn} do
      {item, _release} = tracked_with_release(%{name: "Pennant Show"})

      friend_secret = Secret.wrap(String.duplicate("0", 63) <> "3")
      friend_pubkey = "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
      {:ok, _} = Social.add_friend(friend_pubkey, "Sample Friend")

      title =
        Title.new!(%{
          tmdb_id: item.tmdb_id,
          media_type: item.media_type,
          name: "Pennant Show"
        })

      event =
        Event.sign(
          Translation.to_event(
            :review,
            title,
            [text: "Worth the wait.", sentiment: :love],
            friend_pubkey
          ),
          friend_secret
        )

      # Ingesting a friend's act warms the title's artwork.
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_get_tv(
        item.tmdb_id,
        TmdbStubs.tv_detail(%{"id" => item.tmdb_id, "name" => "Pennant Show"})
      )

      {:ok, _rec} = Activities.ingest(event)
      await_supervised_tasks()

      {:ok, view, _html} = live_async!(conn, "/downloads?title=tv_series-#{item.tmdb_id}")

      assert has_element?(view, "#detail-modal[data-state=open]")
      # What friends did is the social capsule, on every title surface —
      # this one included, now that the host reads it by identity.
      assert has_element?(
               view,
               "#detail-social .social-glyph[data-flag='love'][data-tip*='Sample Friend']"
             )
    end

    test "a deep link to a series the library owns renders its seasons and offers Play", %{conn: conn} do
      series = create_tv_series(%{name: "Owned Show", tmdb_id: "246810"})
      season = create_season(%{tv_series_id: series.id, season_number: 1})

      _ =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Episode S1E1",
          content_url: "/tv/owned-show/s01e01.mkv"
        })

      {:ok, view, _html} = live_async!(conn, "/downloads?title=tv_series-246810")

      assert has_element?(view, "#detail-modal[data-state=open]", "Owned Show")
      assert has_element?(view, "#detail-modal [data-nav-zone='detail_list']", "Episode S1E1")
      assert has_element?(view, "#detail-modal button[phx-click='play']")
      refute has_element?(view, "#detail-download")
    end

    test "a link naming a friend's activity shows their words on Downloads too — read by identity",
         %{conn: conn} do
      friend_secret = Secret.wrap(String.duplicate("0", 63) <> "3")
      friend_pubkey = "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
      {:ok, _} = Social.add_friend(friend_pubkey, "Sample Friend")

      title = Title.new!(%{tmdb_id: 424_242, media_type: :movie, name: "Noted Movie"})

      event =
        Event.sign(
          Translation.to_event(
            :review,
            title,
            [text: "Worth the wait.", sentiment: :love],
            friend_pubkey
          ),
          friend_secret
        )

      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_get_movie(
        424_242,
        TmdbStubs.movie_detail(%{"id" => 424_242, "title" => "Noted Movie"})
      )

      {:ok, rec} = Activities.ingest(event)
      await_supervised_tasks()

      # The activity's own snapshot opens the title — no page row, no fetch.
      {:ok, view, _html} = live_async!(conn, "/downloads?title=movie-424242&activity=#{rec.id}")

      assert has_element?(view, "#detail-modal[data-state=open]", "Noted Movie")
      assert has_element?(view, "#detail-note", "Sample Friend")
      assert has_element?(view, "#detail-note", "Worth the wait.")
    end

    test "mounting with ?title= opens the modal directly (shareable URL)", %{conn: conn} do
      {item, _release} = tracked_with_release(%{name: "Deep Link Show"})

      {:ok, view, _html} = live_async!(conn, "/downloads?title=tv_series-#{item.tmdb_id}")

      assert has_element?(view, "#detail-modal[data-state=open]")
      assert render(view) =~ "Deep Link Show"
    end

    test "a deep link to a title this page does not know, without TMDB, says what it needs and drops the param",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/downloads?title=tv_series-424242")

      render_async(view, 1_000)
      assert_patch(view, "/downloads")
      assert has_element?(view, "#detail-modal[data-state=closed]")
      assert render(view) =~ "TMDB API key"
    end

    test "a deep link to a series no list knows opens the modal from TMDB", %{conn: conn} do
      enable_tmdb!()
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_get_tv(
        424_242,
        TmdbStubs.tv_detail(%{
          "id" => 424_242,
          "name" => "Unlisted Show",
          "first_air_date" => "2012-03-04"
        })
      )

      {:ok, view, _html} = live_async!(conn, "/downloads?title=tv_series-424242")

      html = render_async(view, 1_000)
      assert has_element?(view, "#detail-modal[data-state=open]")
      assert html =~ "Unlisted Show"

      assert has_element?(
               view,
               "#detail-watchlist-toggle[aria-pressed='false'][phx-value-choice='list']"
             )
    end
  end

  describe "tracking management" do
    test "the rows move the rung; the bookmark deletes the tracked title and its row", %{conn: conn} do
      {item, _release} = tracked_with_release(%{name: "Mode Show"})

      {:ok, view, _html} = live_async!(conn, "/downloads?title=tv_series-#{item.tmdb_id}")

      # Tracked at Grab: Auto-grab holds the Track row on.
      assert has_element?(view, "#detail-tracking-controls-track[aria-disabled='true']")

      view |> element("#detail-tracking-controls-grab") |> render_click()
      assert Watchlist.rung(item.tmdb_id, item.media_type) == :follow
      assert has_element?(view, "#detail-tracking-controls-track[phx-value-choice='list']")

      view |> element("#detail-tracking-controls-grab") |> render_click()
      assert Watchlist.rung(item.tmdb_id, item.media_type) == :grab

      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Watchlist.rung(item.tmdb_id, item.media_type) == nil
      refute ReleaseTracking.get_item(item.id), "Off deletes the tracked title"
      # Nothing is tracked, so there is no calendar to read dates from; the
      # modal itself stays (the test below).
      refute has_element?(view, "#detail-release-dates")
    end

    test "the bookmark leaves the modal open once the tracked title is gone — the toggle is its own undo",
         %{conn: conn} do
      {item, _release} = tracked_with_release(%{name: "Kept Show"})

      {:ok, view, _html} = live_async!(conn, "/downloads?title=tv_series-#{item.tmdb_id}")

      view |> element("#detail-watchlist-toggle") |> render_click()
      assert Watchlist.rung(item.tmdb_id, item.media_type) == nil
      refute ReleaseTracking.get_item(item.id)

      # This page knew the title through the tracked title, which Off
      # deleted: the open detail keeps its own snapshot.
      assert has_element?(
               view,
               "#detail-modal[data-state='open'] #detail-watchlist-toggle[aria-pressed='false'][phx-value-choice='list']"
             )

      assert render(view) =~ "Kept Show"

      # Re-listing fetches the title's artwork.
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_get_tv(
        item.tmdb_id,
        TmdbStubs.tv_detail(%{"id" => item.tmdb_id, "name" => "Kept Show"})
      )

      view |> element("#detail-watchlist-toggle") |> render_click()
      await_supervised_tasks()
      assert Watchlist.rung(item.tmdb_id, item.media_type) == :list
      assert has_element?(view, "#detail-watchlist-toggle[aria-pressed='true'][phx-value-choice='off']")
    end

    test "the title modal surfaces the per-title lower-quality acceptance and resets it", %{
      conn: conn
    } do
      {item, _release} = tracked_with_release(%{name: "Accepted Show"})

      {:ok, _params} =
        TitleDownloadParams.put(item.tmdb_id, item.media_type, %{
          min_quality: "any"
        })

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?title=tv_series-#{item.tmdb_id}")

      assert has_element?(view, "#detail-lower-quality")

      view
      |> element("#detail-lower-quality button[phx-click='reset_lower_quality']")
      |> render_click()

      assert TitleDownloadParams.get(item.tmdb_id, item.media_type).min_quality ==
               nil

      refute has_element?(view, "#detail-lower-quality")
    end

    test "the title modal shows no acceptance row while the title has none", %{
      conn: conn
    } do
      {item, _release} = tracked_with_release(%{name: "Default Show"})

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?title=tv_series-#{item.tmdb_id}")

      assert has_element?(view, "#detail-tracking-controls")
      refute has_element?(view, "#detail-lower-quality")
    end
  end

  describe "page artwork" do
    test "the search page carries the calm scrim only — no backdrop, even with candidates",
         %{conn: conn} do
      movie = create_standalone_movie(%{name: "Sample Movie", description: "A synopsis"})
      create_linked_file(%{movie_id: movie.id})

      create_image(%{
        movie_id: movie.id,
        role: "backdrop",
        content_url: "#{movie.id}/backdrop.jpg",
        extension: "jpg"
      })

      # hero_candidates reads a global ETS projection; refresh it from this
      # test's sandboxed rows. With the projection populated, a backdrop
      # would render if one were wired.
      MediaCentaur.Library.Views.HeroCandidates.refresh_cache()

      {:ok, view, _html} = live_async!(conn, "/downloads")

      assert has_element?(view, ".page-side-dim.page-side-dim-calm")
      refute has_element?(view, ~s|canvas[phx-hook="HeroBackdrop"]|)
    end
  end

  defp stub_lower_quality_movie do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/indexer"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/indexerstatus"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/search"} ->
          %{"query" => query} = URI.decode_query(conn.query_string)

          results =
            if query == "Sample Movie 2005" do
              [
                %{
                  "title" => "Sample.Movie.2005.720p.WEBRip.x264",
                  "guid" => "bf-720p",
                  "indexerId" => 1,
                  "seeders" => 9,
                  "size" => 1_400_000_000,
                  "indexer" => "indexer-a"
                }
              ]
            else
              []
            end

          Req.Test.json(conn, results)

        {"POST", "/api/v1/search"} ->
          Req.Test.json(conn, %{"approved" => true})

        _other ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  describe "a missing episode of an owned series, from the title detail on Downloads" do
    setup do
      TmdbStubs.stub_series_universe_for_targeting()

      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Settings.Config, :config},
        config
        |> Map.put(:download_client_type, "qbittorrent")
        |> Map.put(:download_client_url, "http://qbit.test")
      )

      Capabilities.save_test_result(:download_client, :ok)
      Capabilities.refresh_cache()
      :ok
    end

    # The board is Downloads' own modal: landing on it from here is a
    # patch that swaps the title detail for it, never a full navigate.
    test "under manual selection the plan's board opens by a patch", %{conn: conn} do
      series = create_tv_series(%{name: "Sample Show", tmdb_id: "246810"})

      season =
        create_season(%{
          tv_series_id: series.id,
          season_number: 1,
          episode_list: [
            %{episode_number: 1, name: "Pilot", air_date: "2020-01-01"},
            %{episode_number: 2, name: "Second Sample", air_date: "2020-01-08"}
          ]
        })

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/tv/sample-show/s01e01.mkv"
      })

      {:ok, view, _html} = live_async!(conn, ~p"/downloads?title=tv_series-246810")

      view
      |> element("[data-role='missing-episode-row'][phx-value-episode='2']")
      |> render_click()

      render_async(view, 2_000)

      assert [plan] = Plans.list_drafts()
      assert plan.approval_policy == "review"
      assert_patch(view, "/downloads?plan=#{plan.id}")
      assert has_element?(view, "#plan-modal[data-state='open']")
      refute has_element?(view, "#detail-modal[data-state='open']")
    end
  end
end
