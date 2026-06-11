defmodule MediaCentaurWeb.AcquisitionLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaurWeb.AcquisitionLive.SearchSession
  alias MediaCentaur.Acquisition.Pursuits.Units
  alias MediaCentaur.Downloads.DownloadClient.QBittorrent
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.Acquisition.{Target, TargetEvents}
  alias MediaCentaur.Search.Prowlarr
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Secret

  # `AcquisitionLive.ensure_loaded/1` defers the initial reads (search
  # session, capability flag, active pursuit rows, history rows) to an
  # owned `start_async(:acquisition_load, …)` (ADR-049). `render_async/1`
  # awaits it deterministically — no wall-clock sleep.
  defp render_after_async_load(view) do
    render_async(view)
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
    client = Req.new(plug: {Req.Test, :prowlarr}, retry: false, base_url: "http://prowlarr.test")
    :persistent_term.put({Prowlarr, :client}, client)

    config = :persistent_term.get({MediaCentaur.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Config, :config},
      Map.merge(config, %{
        prowlarr_url: "http://prowlarr.test",
        prowlarr_api_key: Secret.wrap("test-key"),
        download_client_type: "qbittorrent",
        download_client_url: "http://qb.test"
      })
    )

    # The /download page is now gated on explicit green connection tests
    # for Prowlarr (and the queue section on the download client). Seed
    # both so tests of other behaviors see the fully-enabled page.
    Capabilities.save_test_result(:prowlarr, :ok)
    Capabilities.save_test_result(:download_client, :ok)

    # The SearchSession GenServer is a singleton — reset it between tests
    # so leaked state from a prior test doesn't leak into the next one.
    SearchSession.clear()

    on_exit(fn ->
      :persistent_term.erase({Prowlarr, :client})
      :persistent_term.put({MediaCentaur.Config, :config}, config)
      SearchSession.clear()
    end)

    :ok
  end

  # The release-search form lives behind the omnibox mode flip
  # (UIDR-014) — fresh mounts open in media mode; an active session
  # auto-resumes release mode, so re-mounts don't need the flip.
  defp enter_release_mode(view) do
    view
    |> element("button[phx-click='omnibox_mode'][phx-value-mode='release']")
    |> render_click()
  end

  describe "mount" do
    test "redirects to library when Prowlarr is not configured", %{conn: conn} do
      config = :persistent_term.get({MediaCentaur.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Config, :config},
        Map.merge(config, %{prowlarr_url: nil, prowlarr_api_key: nil})
      )

      assert {:error, {:live_redirect, %{to: "/"}}} = live_async!(conn, ~p"/download")
    end

    test "redirects to library when Prowlarr is configured but untested", %{conn: conn} do
      Capabilities.clear_test_result(:prowlarr)

      assert {:error, {:live_redirect, %{to: "/"}}} = live_async!(conn, ~p"/download")
    end

    test "hides the active-downloads queue when the download client is untested",
         %{conn: conn} do
      Capabilities.clear_test_result(:download_client)

      {:ok, _view, html} = live_async!(conn, ~p"/download")

      refute html =~ "Downloading"
      assert html =~ "Connect a download client"
    end

    test "renders the download page when Prowlarr is configured", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, ~p"/download")

      assert html =~ "Download"
      assert html =~ "data-page-behavior=\"download\""
      assert html =~ "data-nav-default-zone=\"pursuits\""
    end

    test "first paint (disconnected render) reflects loaded capability, not the unloaded default",
         %{conn: conn} do
      # Desktop first-paint correctness: setup marks :download_client :ok, so
      # the load (which runs on the disconnected render) must surface the
      # enabled queue section. The previously-gated behavior left
      # `download_client_ready` at its mount default (false) on the static
      # render and flashed the "Connect a download client" empty state.
      html = conn |> get(~p"/download") |> html_response(200)

      refute html =~ "Connect a download client",
             "download-client capability must be loaded on the disconnected first paint"
    end
  end

  describe "query_change" do
    test "updates expansion preview for valid syntax", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

      html =
        view
        |> form("form[phx-change='query_change']", query: "Sample Show S01E{01-10}")
        |> render_change()

      assert html =~ "10 queries in parallel"
    end

    test "shows error for invalid brace syntax", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

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
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

      refute has_element?(view, "section[data-nav-zone='omnibox'] button[type='submit']")
    end

    test "submitting a fresh valid query starts a search (Enter path)", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

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

    test "the TV picker header renders the series poster", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=new&tmdb_id=246810&tmdb_type=tv")
      render_async(view)

      # tv_detail fixture default poster, w154 for the larger header slot.
      assert has_element?(
               view,
               "[data-plan-modal] img[src='https://image.tmdb.org/t/p/w154/ggFHVNu6YYI5L9pCfOacjizRGt.jpg']"
             )
    end

    test "the picker's seasons start collapsed and expand on demand", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=new&tmdb_id=246810&tmdb_type=tv")
      render_async(view)

      # Collapsed by default — the season header renders, the episode rows don't.
      assert has_element?(view, "[phx-click='plan_toggle_season_expand'][phx-value-season='1']")
      refute has_element?(view, "#plan-episode-1-1")

      view
      |> element("[phx-click='plan_toggle_season_expand'][phx-value-season='1']")
      |> render_click()

      assert has_element?(view, "#plan-episode-1-1")

      view
      |> element("[phx-click='plan_toggle_season_expand'][phx-value-season='1']")
      |> render_click()

      refute has_element?(view, "#plan-episode-1-1")
    end

    test "the movie confirm stage renders the movie poster", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_get_movie(550, TmdbStubs.movie_detail())

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=new&tmdb_id=550&tmdb_type=movie")
      html = render_async(view)

      assert html =~ "Sample Movie"

      # movie_detail fixture default poster.
      assert has_element?(
               view,
               "[data-plan-modal] img[src='https://image.tmdb.org/t/p/w154/pB8BM7pdSp6B6Ih7QI4S2t0POD5.jpg']"
             )
    end

    test "the movie confirm stage shows identity-confirming facts from TMDB", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()
      TmdbStubs.stub_get_movie(550, TmdbStubs.movie_detail())

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=new&tmdb_id=550&tmdb_type=movie")
      html = render_async(view)

      # movie_detail fixture: overview, 139min runtime, Drama genre.
      assert html =~ "A sample movie overview."
      assert html =~ "2h 19m"
      assert html =~ "Drama"
    end

    test "the whole door: pick → picker defaults → plan → board → approve → pursuit modal", %{
      conn: conn
    } do
      stub_plan_tmdb()
      stub_plan_prowlarr()

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=new&tmdb_id=246810&tmdb_type=tv")

      # Targeting stage loads async; default preset = everything aired.
      html = render_async(view)
      assert html =~ "Sample Show"
      assert html =~ "2 selected"
      assert html =~ "Plan 2 episodes"

      # Seasons start collapsed — episode rows appear only after expanding.
      view
      |> element("[phx-click='plan_toggle_season_expand'][phx-value-season='1']")
      |> render_click()

      # Unchecking one unit updates the live count.
      view
      |> element("[phx-click='plan_toggle_unit'][phx-value-season='1'][phx-value-episode='2']")
      |> render_click()

      assert render(view) =~ "1 selected"

      view
      |> element("[phx-click='plan_preset'][phx-value-preset='everything_aired']")
      |> render_click()

      # A live omnibox query survives the picker being open…
      view
      |> form("form[phx-change='omnibox_change']", %{query: "z"})
      |> render_change()

      assert render(view) =~ ~s(value="z")

      # Create: inline Oban solves immediately; the patch carries the plan id.
      view
      |> element("button[phx-click='plan_create']")
      |> render_click()

      _ = render(view)
      [draft] = Plans.list_drafts()
      assert_patch(view, "/download?plan=#{draft.id}")

      # …but materializing the intent into a draft resets the omnibox.
      refute render(view) =~ ~s(value="z")

      # The board: ready, both cells assigned to the pack (a capsule),
      # the release row beneath, approve enabled.
      html = render(view)
      assert html =~ "Plan ready · 2 of 2 covered"
      assert html =~ "Sample.Show.S01.COMPLETE.1080p.WEB-DL"
      assert html =~ "Season 1 pack"
      assert html =~ "Approve &amp; grab"

      view
      |> element("button[phx-click='plan_approve']")
      |> render_click()

      # Approval grabs run async (the LV must stay responsive).
      _ = render_async(view)
      _ = render(view)

      # Approval hands off to the pursuit modal — the board became the pursuit.
      {:ok, plan} = Plans.get(draft.id)
      assert plan.status == "committed"
      assert_patch(view, "/download?selected=#{plan.pursuit_id}")

      units = Units.for_pursuit(plan.pursuit_id)
      assert length(units) == 2
    end

    test "the swap picker: find-more live-fills alternatives; choosing reassigns the unit", %{
      conn: conn
    } do
      stub_plan_tmdb()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
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

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=#{plan.id}")

      [unit | _] = Plans.units_for(plan.id)

      view
      |> element("button[phx-click='plan_show_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      # The descent never searched episode terms — the picker starts empty.
      html = render(view)
      assert html =~ "Nothing else in the corpus yet"
      refute html =~ "Sample.Show.S01E01.2160p.WEB-DL.x265"

      view
      |> element("button[phx-click='plan_find_more_alternatives'][phx-value-unit-id='#{unit.id}']")
      |> render_click()

      html = render_async(view)
      assert html =~ "Sample.Show.S01E01.2160p.WEB-DL.x265"
      assert html =~ "Exclude this release"

      view
      |> element("button[phx-click='plan_choose_release'][phx-value-guid='ui-uhd']")
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

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=#{plan.id}")

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

      html = render_async(view)
      assert html =~ "Find more"
      refute html =~ "Searching…"
    end

    test "the board narrates the descent as status events land", %{conn: conn} do
      stub_plan_tmdb()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
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

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=#{plan.id}")

      # Ready board, no descent event yet, panel not seeded (only
      # still-planning boards seed the initial itinerary).
      html = render(view)
      refute html =~ "Planning the search"

      send(view.pid, %PlanEvents.DescentStatus{
        plan_id: plan.id,
        wanted: 2,
        stages: [
          %{id: :series, state: :done, term_count: 1, residual_after: 2},
          %{id: :seasons, state: :done, term_count: 2, residual_after: 0},
          %{id: :episodes, state: :skipped, term_count: nil, residual_after: nil}
        ]
      })

      html = render(view)
      assert html =~ "Everything covered — the deeper searches weren&#39;t needed."
      assert html =~ "not needed — already covered"

      # A board reload for the SAME plan (Changed event) must not reset
      # the live panel back to the initial itinerary.
      send(view.pid, %PlanEvents.Changed{plan_id: plan.id, status: "ready"})

      html = render(view)
      assert html =~ "Everything covered — the deeper searches weren&#39;t needed."

      # A status for some other plan must not clobber the open board's panel.
      send(view.pid, %PlanEvents.DescentStatus{
        plan_id: Ecto.UUID.generate(),
        wanted: 9,
        stages: [
          %{id: :series, state: :active, term_count: 1, residual_after: nil},
          %{id: :seasons, state: :pending, term_count: nil, residual_after: nil},
          %{id: :episodes, state: :pending, term_count: nil, residual_after: nil}
        ]
      })

      html = render(view)
      assert html =~ "Everything covered — the deeper searches weren&#39;t needed."
    end

    test "a draft plan resumes from the page and can be discarded", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, plan} =
        Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})

      {:ok, view, _html} = live_async!(conn, ~p"/download")

      assert has_element?(view, "#plan-draft-#{plan.id}")

      view
      |> element("#plan-draft-#{plan.id} button[phx-click='resume_plan']")
      |> render_click()

      assert_patch(view, "/download?plan=#{plan.id}")

      view
      |> element("button[phx-click='plan_discard_prompt']")
      |> render_click()

      view
      |> element("button[phx-click='plan_discard_confirm']")
      |> render_click()

      _ = render(view)
      assert_patch(view, "/download")

      {:ok, discarded} = Plans.get(plan.id)
      assert discarded.status == "discarded"
      refute has_element?(view, "#plan-draft-#{plan.id}")
    end

    test "discarding a draft plan requires confirmation", %{conn: conn} do
      stub_plan_tmdb()

      {:ok, plan} =
        Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie"})

      {:ok, view, _html} = live_async!(conn, ~p"/download")

      view
      |> element("#plan-draft-#{plan.id} button[phx-click='resume_plan']")
      |> render_click()

      assert_patch(view, "/download?plan=#{plan.id}")

      # The footer button only prompts — the plan is untouched.
      html =
        view
        |> element("button[phx-click='plan_discard_prompt']")
        |> render_click()

      assert html =~ "Discard plan?"
      {:ok, untouched} = Plans.get(plan.id)
      refute untouched.status == "discarded"

      # Keep — the confirmation closes, the draft survives.
      html =
        view
        |> element("button[phx-click='plan_discard_cancel']")
        |> render_click()

      refute html =~ "Discard plan?"
      {:ok, kept} = Plans.get(plan.id)
      refute kept.status == "discarded"
    end

    test "gaps row offers the live track-later handoff (ADR-056)", %{conn: conn} do
      stub_plan_tmdb()

      # Default Prowlarr stub returns nothing — every wanted unit is a gap.
      {:ok, plan} = Plans.create_series_plan(stub_selection(), [{1, 1}, {1, 2}])

      {:ok, view, _html} = live_async!(conn, ~p"/download?plan=#{plan.id}")
      html = render(view)

      assert html =~ "not available right now"
      # Wired, not disabled — the click path itself (track creation +
      # gap wants) is covered synchronously in tracking_handoffs_test.
      assert has_element?(view, "button[phx-click='plan_track_gaps']", "Track these later")
      refute has_element?(view, "button[disabled]", "Track these later")
    end

    test "no pursuits renders no empty-state banner — the omnibox is the affordance", %{
      conn: conn
    } do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      refute has_element?(view, "section", "No active pursuits")
      refute has_element?(view, "button", "Search for something to watch")
    end
  end

  describe "omnibox — one search surface, two modes (UIDR-014)" do
    test "typing in media mode surfaces TMDB results; picking patches into the plan flow", %{
      conn: conn
    } do
      TmdbStubs.setup_tmdb_client()

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

      {:ok, view, html} = live_async!(conn, ~p"/download")

      # Media mode is the fresh-mount default; no release form visible.
      assert html =~ "What do you want to watch?"
      refute has_element?(view, "form[phx-change='query_change']")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      html = render_async(view)
      assert html =~ "Sample Movie"
      assert html =~ "Sample Show"

      # Picking a result opens the plan flow via URL patch (refresh-safe).
      view
      |> element("#omnibox-result-tv_series-246810")
      |> render_click()

      assert_patch(view, "/download?plan=new&tmdb_id=246810&tmdb_type=tv")
    end

    test "media-mode results render TMDB poster thumbnails, icon fallback without one", %{
      conn: conn
    } do
      TmdbStubs.setup_tmdb_client()

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

      {:ok, view, _html} = live_async!(conn, ~p"/download")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      render_async(view)

      assert has_element?(
               view,
               "#omnibox-result-movie-777 img[src='https://image.tmdb.org/t/p/w92/sample-movie-poster.jpg']"
             )

      # No poster on the TV result — icon placeholder, never a broken image.
      refute has_element?(view, "#omnibox-result-tv_series-246810 img")
    end

    test "the dropdown shows the full first TMDB page, not just eight", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()

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

      {:ok, view, _html} = live_async!(conn, ~p"/download")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      render_async(view, 2000)

      # Result #9 was the first casualty of the old Enum.take(8) cap.
      assert has_element?(view, "#omnibox-result-movie-1009")
      assert has_element?(view, "#omnibox-result-movie-1020")
      # One TMDB page is the ceiling — depth past 20 is a query-refinement
      # problem, not a pagination problem.
      refute has_element?(view, "#omnibox-result-movie-1021")
    end

    test "a re-fire of the same effective query never searches TMDB again", %{conn: conn} do
      TmdbStubs.setup_tmdb_client()

      TmdbStubs.stub_search_multi([
        %{
          "id" => 777,
          "media_type" => "movie",
          "title" => "Sample Movie",
          "release_date" => "2010-03-05"
        }
      ])

      {:ok, view, _html} = live_async!(conn, ~p"/download")

      view
      |> form("form[phx-change='omnibox_change']", %{query: "sample"})
      |> render_change()

      # Generous deadline: the omnibox async runs a stubbed TMDB call
      # plus a Repo read; the 100ms render_async default flakes under
      # load (observed in isolation, 2026-06-10).
      html = render_async(view, 2000)
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

    test "the mode flip swaps in the full release-search form and back", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)
      assert has_element?(view, "form[phx-change='query_change']")
      assert has_element?(view, "form[phx-change='query_change'] input[name='query']")

      view
      |> element("button[phx-click='omnibox_mode'][phx-value-mode='media']")
      |> render_click()

      refute has_element?(view, "form[phx-change='query_change']")
      assert has_element?(view, "form[phx-change='omnibox_change']")
    end

    test "an active release session resumes in release mode on a fresh mount", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")
      enter_release_mode(view)

      view
      |> form("form[phx-change='query_change']", query: "Sample Show S01E0{1,2}")
      |> render_change()

      # Re-mount: the in-flight session must not hide behind media mode.
      {:ok, view, _html} = live_async!(conn, ~p"/download")
      assert has_element?(view, "form[phx-change='query_change']")
    end
  end

  describe "submit_search and grab_selected" do
    test "renders results, lets user select, and submits a grab", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

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
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn ->
        # Grabs POST to /api/v1/search too (the Prowlarr grab gotcha) —
        # discriminate searches from grabs by method.
        case {conn.method, conn.request_path} do
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

      qbit_client =
        Req.new(plug: {Req.Test, :qbittorrent}, retry: false, base_url: "http://qbit.test")

      :persistent_term.put({QBittorrent, :client}, qbit_client)

      config = :persistent_term.get({MediaCentaur.Config, :config})

      :persistent_term.put(
        {MediaCentaur.Config, :config},
        Map.merge(config, %{
          download_client_type: "qbittorrent",
          download_client_url: "http://qbit.test",
          download_client_username: "alice",
          download_client_password: Secret.wrap("s3cret")
        })
      )

      on_exit(fn ->
        :persistent_term.put({MediaCentaur.Config, :config}, config)
        QBittorrent.invalidate_client()
      end)

      :ok
    end

    alias MediaCentaur.Downloads.QueueItem

    test "confirming the modal calls qBittorrent delete and clears the row", %{conn: conn} do
      delete_counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/v2/torrents/delete"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            assert body == "hashes=hash-a&deleteFiles=true"
            :counters.add(delete_counter, 1, 1)
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/download")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      # Seed the queue via the same PubSub broadcast QueueMonitor emits.
      send(
        view.pid,
        {:queue_state,
         %MediaCentaur.Downloads.QueueState{
           items: [
             %QueueItem{
               id: "hash-a",
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
      assert html =~ "phx-click=\"cancel_download_prompt\""

      # Open the confirmation modal.
      html =
        view
        |> element("button[phx-click='cancel_download_prompt']")
        |> render_click()

      assert html =~ "Cancel download?"

      # Confirm — fires the qBittorrent delete and optimistically drops the row.
      html =
        view
        |> element("button[phx-click='cancel_download_confirm']")
        |> render_click()

      assert :counters.get(delete_counter, 1) == 1
      refute html =~ "phx-value-id=\"hash-a\""
      refute html =~ "Cancel download?"
    end

    test "ghost row from a stale snapshot does not reappear after cancel", %{conn: conn} do
      # Regression: the LiveView used to overwrite active_queue on every
      # snapshot. If qBittorrent's DELETE took >1 polling cycle to
      # propagate, the next snapshot brought the cancelled row back —
      # the user saw "they just sit there".
      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/v2/torrents/delete"} -> Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/download")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      stale_item = %QueueItem{
        id: "ghost-1",
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
      assert render(view) =~ "phx-value-id=\"ghost-1\""

      view |> element("button[phx-click='cancel_download_prompt']") |> render_click()
      view |> element("button[phx-click='cancel_download_confirm']") |> render_click()

      # Simulate the next poll arriving before qBittorrent has propagated
      # the deletion — the same item shows up in the snapshot. The LiveView
      # must keep it hidden during the cancel grace window.
      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [stale_item]}})

      # Use the row's phx-value-id rather than the title — the title also
      # appears in the post-cancel flash, which would mask a real failure.
      refute render(view) =~ "phx-value-id=\"ghost-1\""
    end

    test "dismissing the modal does not call qBittorrent delete", %{conn: conn} do
      delete_counter = :counters.new(1, [:atomics])

      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/v2/torrents/delete"} ->
            :counters.add(delete_counter, 1, 1)
            Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/download")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      send(
        view.pid,
        {:queue_state,
         %MediaCentaur.Downloads.QueueState{
           items: [
             %QueueItem{
               id: "hash-b",
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
        |> element("button[phx-click='cancel_download_prompt']")
        |> render_click()

      assert html =~ "Cancel download?"

      html =
        view
        |> element("button[phx-click='cancel_download_cancel']")
        |> render_click()

      refute html =~ "Cancel download?"
      assert :counters.get(delete_counter, 1) == 0
    end

    test "orphan downloads list keys rows by id and survives mid-list cancel", %{conn: conn} do
      # Regression: Phoenix's positional comprehension diff causes the row
      # at the cancelled position to morph in place into the *next* item's
      # data and the bottom row to disappear when rows lack stable ids.
      # The orphan ("Other downloads") section gives each row its own
      # `id="orphan-{hash}"` so morphdom moves nodes by id even without
      # `phx-update="stream"`.
      Req.Test.stub(:qbittorrent, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/v2/torrents/delete"} -> Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, view, _html} = live_async!(conn, ~p"/download")
      Req.Test.allow(:qbittorrent, self(), view.pid)

      items =
        for {hash, title} <- [
              {"hash-a", "Movie.A.2024"},
              {"hash-b", "Movie.B.2024"},
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
      assert html =~ "Other downloads"
      assert html =~ ~s|id="orphan-hash-a"|
      assert html =~ ~s|id="orphan-hash-b"|
      assert html =~ ~s|id="orphan-hash-c"|

      view |> element("button[phx-value-id='hash-b']") |> render_click()
      html = view |> element("button[phx-click='cancel_download_confirm']") |> render_click()

      # The middle row's id is gone, and the surviving rows keep their ids
      # so morphdom can match them by id rather than morphing positionally.
      assert html =~ ~s|id="orphan-hash-a"|
      refute html =~ ~s|id="orphan-hash-b"|
      assert html =~ ~s|id="orphan-hash-c"|
    end
  end

  describe "retry_search (per-group)" do
    test "a single timed-out search becomes retryable; retry resolves to results",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

      Req.Test.allow(:prowlarr, self(), view.pid)

      # First search — every Prowlarr call fails with a transport timeout.
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      view
      |> form("form[phx-change='query_change']", query: "Movie A")
      |> render_submit()

      html = render_until(view, "Prowlarr timed out")
      # Retry affordance is present alongside the timeout message
      assert html =~ "phx-click=\"retry_search\""
      assert html =~ "phx-value-term=\"Movie A\""

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
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

      Req.Test.allow(:prowlarr, self(), view.pid)

      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      view
      |> form("form[phx-change='query_change']", query: "Sample Show S01E{01,02}")
      |> render_submit()

      html = render_until(view, "Retry 2 timeouts")
      assert html =~ "phx-click=\"retry_all_timeouts\""

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
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      enter_release_mode(view)

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

      html = render_until(view, "Healthy.Result.1080p")
      refute html =~ "retry_all_timeouts"
    end
  end

  describe "debounce on acquisition PubSub events" do
    test "five rapid grab-event broadcasts trigger only one activity reload after the debounce window",
         %{conn: conn} do
      # Regression guard: TargetEvents and related events must be debounced
      # (500ms) rather than calling load_activity on every message. Five events
      # in quick succession must result in one :reload_activity — the page must
      # render correctly after the window without crashing.
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      for _ <- 1..5 do
        send(view.pid, %TargetEvents.Picked{target: %Target{}})
      end

      Process.sleep(600)

      assert render(view) =~ "Download"
    end
  end

  describe "search session persistence" do
    setup do
      SearchSession.clear()
      :ok
    end

    test "search query and results persist across navigation", %{conn: conn} do
      stub_prowlarr_with([sample_release()])

      {:ok, view, _html} = live_async!(conn, "/download")

      enter_release_mode(view)

      view
      |> form("form[phx-change='query_change']", %{"query" => "Sample Show"})
      |> render_submit()

      # The Prowlarr search results arrive asynchronously ({:search_result, …})
      # and re-render the group — poll until they land.
      html = render_until(view, "Sample.Show.S01E01")
      assert html =~ "Sample Show"
      assert html =~ "Sample.Show.S01E01"

      {:ok, _other_view, _other_html} = live_async!(conn, "/")

      {:ok, view2, _html2} = live_async!(conn, "/download")
      html2 = render_after_async_load(view2)

      assert html2 =~ "Sample Show"
      assert html2 =~ "Sample.Show.S01E01"
    end

    test "user-changed selection persists across navigation", %{conn: conn} do
      stub_prowlarr_with([
        sample_release(guid: "guid-1", title: "Sample.Show.S01E01.720p.WEB-DL.mkv"),
        sample_release(guid: "guid-2", title: "Sample.Show.S01E01.1080p.WEB-DL.mkv")
      ])

      {:ok, view, _html} = live_async!(conn, "/download")

      enter_release_mode(view)
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
      {:ok, _view2, _html2} = live_async!(conn, "/download")

      session_after = SearchSession.current()
      assert session_after.selections == %{"Sample Show" => "guid-2"}
    end

    test "groups in :loading become :abandoned with retry affordance after LV crash", %{conn: conn} do
      Req.Test.stub(:prowlarr, fn _conn ->
        :timer.sleep(:infinity)
      end)

      {:ok, view, _html} = live_async!(conn, "/download")

      enter_release_mode(view)

      view
      |> form("form[phx-change='query_change']", %{"query" => "Pending Show"})
      |> render_submit()

      session_before = await_session_groups(:loading)
      assert Enum.all?(session_before.groups, fn group -> group.status == :loading end)

      GenServer.stop(view.pid, :normal)

      # The LV crash sweeps in-flight :loading groups to :abandoned via the
      # SearchSession's :DOWN handler — poll the session until it lands.
      session_after = await_session_groups(:abandoned)
      assert Enum.all?(session_after.groups, fn group -> group.status == :abandoned end)

      {:ok, view2, _html2} = live_async!(conn, "/download")
      assert render_after_async_load(view2) =~ "Retry"
    end
  end

  describe "live updates from queue monitor" do
    # The active queue is now driven by QueueMonitor's PubSub broadcast
    # rather than per-LV polling. The LV must consume {:queue_state, %QueueState{items: items}}
    # and re-render the queue zone without making its own download-client
    # call. Without this contract the page would silently regress to stale
    # data after the polling timer was removed.

    alias MediaCentaur.Downloads.QueueItem

    test "queue_snapshot broadcast paints the active queue",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

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
      # completed entries must not surface seeded torrents on /download.
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      done = %QueueItem{id: "h1", title: "Already Done Movie", state: :completed}
      live_item = %QueueItem{id: "h2", title: "Still Downloading Movie", state: :downloading}

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [done, live_item]}})

      html = render(view)
      refute html =~ "Already Done Movie"
      assert html =~ "Still Downloading Movie"
    end

    test "empty queue_snapshot transitions to the empty state",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      seed = %QueueItem{id: "h3", title: "Soon To Vanish", state: :downloading}
      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [seed]}})
      assert render(view) =~ "Soon To Vanish"

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: []}})

      html = render(view)
      refute html =~ "Soon To Vanish"
      refute html =~ "Other downloads"
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

      qbit_client =
        Req.new(plug: {Req.Test, :qbittorrent}, retry: false, base_url: "http://qbit.test")

      :persistent_term.put({QBittorrent, :client}, qbit_client)
      on_exit(fn -> QBittorrent.invalidate_client() end)

      monitor = start_supervised!(MediaCentaur.Downloads.QueueMonitor)
      Req.Test.allow(:qbittorrent, self(), monitor)

      {:ok, view, _html} = live_async!(conn, ~p"/download")

      # Drain any racing mount-time poll so the subsequent assert_receive
      # observes the post-:capabilities_changed call specifically.
      receive do
        :qbit_called -> :ok
      after
        500 -> :ok
      end

      send(view.pid, :capabilities_changed)

      assert_receive :qbit_called, 1_000
    end
  end

  describe "pursuits paired with their live downloads" do
    import MediaCentaur.TestFactory

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

    test "a matched queue item renders as a footer under the right pursuit card",
         %{conn: conn} do
      pursuit = pursuit_with_acquired_target("Sample Movie 2010", "Sample.Movie.2010.1080p.WEB-DL")

      {:ok, view, _html} = live_async!(conn, "/download")

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
      # Matched items don't surface in the "Other downloads" section.
      refute html =~ "Other downloads"
    end

    test "an unmatched queue item appears under 'Other downloads', and the pursuit shows its no-match hint",
         %{conn: conn} do
      _pursuit = pursuit_with_acquired_target("Sample Movie 2010", "Sample.Movie.2010.1080p.WEB-DL")

      {:ok, view, _html} = live_async!(conn, "/download")

      unrelated = %QueueItem{
        id: "hash-orphan",
        title: "Totally.Different.Movie.2024",
        state: :downloading,
        status: "downloading",
        download_client: "qBittorrent"
      }

      send(view.pid, {:queue_state, %MediaCentaur.Downloads.QueueState{items: [unrelated]}})

      html = render(view)
      assert html =~ "Other downloads"
      assert html =~ ~s|id="orphan-hash-orphan"|
      # The pursuit card surfaces `PursuitStatus.derive`'s `CurrentAction`
      # as the status line when no torrent is matched — the acquired-but-
      # not-yet-landed case now reads as the post-download lifecycle stage.
      assert html =~ "Downloaded"
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

      {:ok, view, _html} = live_async!(conn, "/download")

      assert render_after_async_load(view) =~ "Sample Show S01E03"
    end
  end

  describe "history disclosure" do
    # History is terminal-state bookkeeping, not live activity — it sits
    # at the bottom of the page, collapsed by default at every width so
    # the page leads with active pursuits. Collapsed means the zone body
    # (filter chips, search, rows) is not rendered at all; only the
    # disclosure toggle is. The filter chips are the "is the zone
    # expanded?" probe.

    @history_filter_chips "section[data-nav-zone='history'] button[phx-click='set_history_filter']"

    test "history starts collapsed — toggle present, body not rendered", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      assert has_element?(view, "[phx-click='toggle_history']")
      refute has_element?(view, @history_filter_chips)
    end

    test "toggling expands and collapses the zone", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      view |> element("[phx-click='toggle_history']") |> render_click()
      assert has_element?(view, @history_filter_chips)

      view |> element("[phx-click='toggle_history']") |> render_click()
      refute has_element?(view, @history_filter_chips)
    end

    test "deep-linking with history params auto-expands the zone", %{conn: conn} do
      # The upcoming-zone badges link to /download?filter=all&search=<title>
      # — a user following that link came FOR the history zone, so it
      # must not greet them collapsed.
      {:ok, view, _html} = live_async!(conn, ~p"/download?filter=all&search=Sample")

      assert has_element?(view, @history_filter_chips)
    end

    test "opening the pursuit modal does not auto-expand history", %{conn: conn} do
      # build_pursuit_modal_path/2 always carries filter= in the patch URL;
      # only the FIRST load's params may auto-expand, otherwise clicking
      # any pursuit row would pop the history zone open underneath the modal.
      {:ok, view, _html} = live_async!(conn, ~p"/download")

      render_patch(view, "/download?filter=failed&selected=#{Ecto.UUID.generate()}")

      refute has_element?(view, @history_filter_chips)
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
      {:ok, view, _html} = live_async!(conn, "/download")

      for _ <- 1..5 do
        send(view.pid, {:target_failed, %{id: Ecto.UUID.generate(), reason: "boom"}})
      end

      Process.sleep(600)

      # No crash, page still renders History zone.
      assert render(view) =~ "History"
    end

    test "grab_submitted broadcast triggers a debounced reload without crashing",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, "/download")

      send(view.pid, {:target_picked, %{id: Ecto.UUID.generate()}})
      send(view.pid, {:target_armed, %{id: Ecto.UUID.generate()}})
      send(view.pid, {:target_snoozed, %{id: Ecto.UUID.generate()}})

      Process.sleep(600)

      assert render(view) =~ "History"
    end
  end

  # Polls the out-of-band search session (a GenServer updated asynchronously —
  # search dispatch, and the crash-driven :abandoned sweep on the LV's :DOWN)
  # until every group reaches `status` and at least one group exists. The
  # non-empty guard matters: `Enum.all?([], …)` is vacuously true, so without
  # it a poll would pass before the groups were even created. Deterministic
  # stand-in for a settle sleep; returns the session.
  defp await_session_groups(status, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_session_groups(status, deadline)
  end

  defp do_await_session_groups(status, deadline) do
    session = SearchSession.current()

    cond do
      session.groups != [] and Enum.all?(session.groups, &(&1.status == status)) ->
        session

      System.monotonic_time(:millisecond) >= deadline ->
        flunk(
          "search-session groups never all reached #{inspect(status)}; " <>
            "got #{inspect(Enum.map(session.groups, & &1.status))}"
        )

      true ->
        Process.sleep(10)
        do_await_session_groups(status, deadline)
    end
  end
end
