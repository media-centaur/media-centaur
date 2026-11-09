defmodule MediaCentaurWeb.Api.AcquisitionApiTest do
  use MediaCentaurWeb.ApiCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.ProwlarrStubs
  alias MediaCentaur.Search.SearchResult
  alias MediaCentaur.TmdbStubs

  @secret_link "http://prowlarr.test/1/download?apikey=never-shown"

  defp release(guid) do
    %{
      "title" => "Sample.Show.#{guid}.1080p",
      "guid" => guid,
      "indexerId" => 1,
      "downloadUrl" => @secret_link
    }
  end

  defp json_post(conn, path, body) do
    conn |> put_req_header("content-type", "application/json") |> post(path, JSON.encode!(body))
  end

  defp stub_terms(answers) do
    Req.Test.stub(:prowlarr, fn conn ->
      case answers[Plug.Conn.fetch_query_params(conn).query_params["query"]] do
        :fail -> Plug.Conn.send_resp(conn, 500, "indexer down")
        releases -> Req.Test.json(conn, releases || [])
      end
    end)
  end

  setup do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  describe "before Prowlarr is configured" do
    test "searching says so", %{conn: conn} do
      body = conn |> get("/api/v1/releases", q: "Sample") |> json_response(503)
      assert body["error"]["code"] == "not_configured"
      assert_schema(body, "Error")
    end
  end

  describe "releases" do
    setup do
      :ok = ProwlarrStubs.mark_ready!()
    end

    test "a search reports each term, including the one that failed", %{conn: conn} do
      stub_terms(%{"Sample E1" => [release("one")], "Sample E2" => :fail})

      body = conn |> get("/api/v1/releases", q: "Sample E{1,2}", refresh: "true") |> json_response(200)

      assert_schema(body, "ReleaseSearch")

      assert [
               %{"term" => "Sample E1", "status" => "ok", "releases" => [%{"guid" => "one"}]},
               %{"term" => "Sample E2", "status" => "failed", "releases" => []}
             ] = body["terms"]
    end

    test "a release's download link, which can carry Prowlarr's key, is never returned", %{conn: conn} do
      stub_terms(%{"Sample" => [release("one")]})

      response = conn |> get("/api/v1/releases", q: "Sample", refresh: "true") |> response(200)

      refute response =~ "never-shown"
    end

    test "a search without a query is refused", %{conn: conn} do
      assert %{"error" => %{"code" => "invalid_request"}} =
               conn |> get("/api/v1/releases") |> json_response(400)
    end

    test "malformed braces are refused", %{conn: conn} do
      assert %{"error" => %{"code" => "invalid_query"}} =
               conn |> get("/api/v1/releases", q: "Sample {1") |> json_response(422)
    end

    test "a grab starts one pursuit", %{conn: conn} do
      Corpus.record!("Sample", [], [SearchResult.from_prowlarr(release("one"))])

      body =
        conn
        |> json_post("/api/v1/grabs", %{query: "Sample", releases: [%{guid: "one", term: "Sample"}]})
        |> json_response(202)

      assert_schema(body, "Grab")
      assert [%{"guid" => "one"}] = body["grabs"]
      assert is_binary(body["pursuit_id"])
    end

    test "a guid no search has seen is named in the refusal", %{conn: conn} do
      body =
        conn
        |> json_post("/api/v1/grabs", %{query: "Sample", releases: [%{guid: "gone", term: "Sample"}]})
        |> json_response(404)

      assert %{"error" => %{"code" => "release_unavailable", "message" => message}} = body
      assert message =~ "gone"
    end

    test "a malformed grab is refused", %{conn: conn} do
      assert %{"error" => %{"code" => "invalid_request"}} =
               conn |> json_post("/api/v1/grabs", %{query: "Sample", releases: []}) |> json_response(400)

      assert %{"error" => %{"code" => "invalid_request"}} =
               conn
               |> json_post("/api/v1/grabs", %{query: "Sample", releases: [%{guid: "x"}]})
               |> json_response(400)
    end
  end

  describe "titles" do
    test "a search returns TMDB titles with the type a plan takes", %{conn: conn} do
      TmdbStubs.mark_ready!()

      TmdbStubs.stub_search_multi([
        %{"id" => 7, "media_type" => "tv", "name" => "Sample Show", "first_air_date" => "2010-01-01"}
      ])

      body = conn |> get("/api/v1/titles", q: "Sample") |> json_response(200)

      assert_schema(body, "TitleSearch")

      assert [%{"tmdb_id" => 7, "media_type" => "tv", "name" => "Sample Show", "year" => "2010"}] =
               body["titles"]
    end

    test "a TMDB outage is an error, not an empty list", %{conn: conn} do
      TmdbStubs.mark_ready!()
      Req.Test.stub(:tmdb, fn conn -> Plug.Conn.send_resp(conn, 500, "{}") end)

      assert %{"error" => %{"code" => "upstream_error"}} =
               conn |> get("/api/v1/titles", q: "Sample") |> json_response(502)
    end
  end

  describe "plans" do
    setup do
      :ok = ProwlarrStubs.mark_ready!()
      TmdbStubs.stub_get_movie("246813", %{"title" => "Sample Movie", "release_date" => "2005-01-01"})
      :ok
    end

    defp create_plan(conn, attrs \\ %{}) do
      conn
      |> json_post("/api/v1/plans", Map.merge(%{tmdb_id: 246_813, media_type: "movie"}, attrs))
      |> json_response(202)
    end

    test "a plan is created on review unless the caller asks otherwise", %{conn: conn} do
      body = create_plan(conn)

      assert_schema(body, "Plan")
      assert %{"status" => "planning", "approval_policy" => "review", "pursuit_id" => nil} = body
    end

    test "a caller can ask for automatic approval", %{conn: conn} do
      assert %{"approval_policy" => "automatic"} = create_plan(conn, %{approval_policy: "automatic"})
    end

    test "a plan that finds nothing reports it waits for a person", %{conn: conn} do
      %{"id" => id} = create_plan(conn, %{approval_policy: "automatic"})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      body = conn |> get("/api/v1/plans/#{id}") |> json_response(200)

      assert_schema(body, "Plan")
      assert %{"status" => "ready", "awaiting_approval" => true} = body
      assert [%{"status" => "unfound", "gap" => "not_found"}] = body["units"]
    end

    test "asking twice for the same film is a conflict, not a second plan", %{conn: conn} do
      create_plan(conn, %{approval_policy: "automatic"})

      assert %{"error" => %{"code" => "already_downloading"}} =
               conn
               |> json_post("/api/v1/plans", %{tmdb_id: 246_813, media_type: "movie"})
               |> json_response(409)
    end

    test "an automatic plan the gate cannot commit waits for a person and says why", %{conn: conn} do
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, [film_release()]) end)
      %{"id" => id} = create_plan(conn, %{approval_policy: "automatic"})
      create_pursuit(%{tmdb_id: "246813", tmdb_type: "movie", title: "Sample Movie", origin: "manual"})

      ExUnit.CaptureLog.capture_log(fn -> MediaCentaur.JobRuns.run_enqueued_jobs() end)
      body = conn |> get("/api/v1/plans/#{id}") |> json_response(200)

      assert %{"status" => "ready", "approval_policy" => "review", "awaiting_approval" => true} = body
      assert body["error"] =~ "already being downloaded"
    end

    test "an automatic plan that finds its release commits without a person", %{conn: conn} do
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.method do
          "POST" -> Req.Test.json(conn, %{})
          _search -> Req.Test.json(conn, [film_release()])
        end
      end)

      %{"id" => id} = create_plan(conn, %{approval_policy: "automatic"})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      body = conn |> get("/api/v1/plans/#{id}") |> json_response(200)

      assert_schema(body, "Plan")
      assert %{"status" => "committed", "awaiting_approval" => false} = body

      assert [
               %{
                 "status" => "found",
                 "gap" => nil,
                 "release" => %{"guid" => "film", "quality" => "hd_1080p"}
               }
             ] =
               body["units"]

      assert conn
             |> get("/api/v1/pursuits/#{body["pursuit_id"]}")
             |> json_response(200)
             |> assert_schema("PursuitDetail")
    end

    defp film_release do
      %{
        "title" => "Sample.Movie.2005.1080p.WEB-DL.x264-GROUP",
        "guid" => "film",
        "indexerId" => 1,
        "seeders" => 50,
        "size" => 4_000_000_000,
        "protocol" => "torrent"
      }
    end

    test "an unknown or malformed plan id is 404", %{conn: conn} do
      assert conn |> get("/api/v1/plans/not-a-uuid") |> json_response(404)
      assert conn |> get("/api/v1/plans/#{Ecto.UUID.generate()}") |> json_response(404)
    end

    test "a plan stopped on lower quality says so, and accepting it plans again", %{conn: conn} do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [
          %{film_release() | "title" => "Sample.Movie.2005.720p.WEB-DL", "guid" => "film-720p"}
        ])
      end)

      %{"id" => id} = create_plan(conn, %{approval_policy: "automatic"})
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert %{"awaiting_approval" => true, "units" => [%{"gap" => "below_quality"}]} =
               conn |> get("/api/v1/plans/#{id}") |> json_response(200)

      body = conn |> post("/api/v1/plans/#{id}/accept-lower-quality") |> json_response(202)
      assert_schema(body, "Plan")
      assert %{"status" => "planning"} = body
    end

    test "accepting lower quality on a plan that is not ready is a conflict", %{conn: conn} do
      %{"id" => id} = create_plan(conn)
      Plans.fetch(id) |> elem(1) |> force_attrs(%{status: "discarded"})

      assert %{"error" => %{"code" => "plan_not_ready"}} =
               conn |> post("/api/v1/plans/#{id}/accept-lower-quality") |> json_response(409)
    end

    test "approving a plan while it searches is a conflict", %{conn: conn} do
      %{"id" => id} = create_plan(conn)

      assert %{"error" => %{"code" => "plan_not_ready"}} =
               conn |> post("/api/v1/plans/#{id}/approve") |> json_response(409)
    end

    test "approving a plan that found nothing is refused", %{conn: conn} do
      %{"id" => id} = create_plan(conn)
      MediaCentaur.JobRuns.run_enqueued_jobs()

      assert %{"error" => %{"code" => "nothing_to_grab"}} =
               conn |> post("/api/v1/plans/#{id}/approve") |> json_response(422)
    end

    test "a plan can be discarded once", %{conn: conn} do
      %{"id" => id} = create_plan(conn)

      assert %{"status" => "discarded"} =
               conn |> post("/api/v1/plans/#{id}/discard") |> json_response(200)

      assert conn |> post("/api/v1/plans/#{id}/discard") |> json_response(409)
    end

    test "a series plan can name its seasons and episodes", %{conn: conn} do
      TmdbStubs.stub_series_universe_for_targeting()

      body =
        conn
        |> json_post("/api/v1/plans", %{
          tmdb_id: 246_810,
          media_type: "tv",
          episodes: [%{season: 1, episode: 2}, %{season: 2}]
        })
        |> json_response(202)

      assert_schema(body, "Plan")

      assert [
               %{"season_number" => 1, "episode_number" => 2},
               %{"season_number" => 2, "episode_number" => 1}
             ] =
               body["units"]
    end

    test "episodes are refused beside a scope, for a film, or malformed", %{conn: conn} do
      for attrs <- [
            %{tmdb_id: 246_810, media_type: "tv", scope: "everything", episodes: [%{season: 1}]},
            %{tmdb_id: 246_813, media_type: "movie", episodes: [%{season: 1}]},
            %{tmdb_id: 246_810, media_type: "tv", episodes: []},
            %{tmdb_id: 246_810, media_type: "tv", episodes: [%{episode: 2}]}
          ] do
        assert %{"error" => %{"code" => "invalid_request"}} =
                 conn |> json_post("/api/v1/plans", attrs) |> json_response(400)
      end
    end

    test "a title's state says what the library has and what is planned or downloading", %{conn: conn} do
      %{"id" => plan_id} = create_plan(conn)

      body = conn |> get("/api/v1/titles/movie/246813") |> json_response(200)

      assert_schema(body, "TitleState")

      assert %{
               "tmdb_id" => 246_813,
               "media_type" => "movie",
               "in_library" => false,
               "auto_grab" => false,
               "state" => "planning",
               "plan_ids" => [^plan_id],
               "pursuit_ids" => []
             } = body

      assert %{"error" => %{"code" => "invalid_request"}} =
               conn |> get("/api/v1/titles/film/246813") |> json_response(400)
    end

    test "auto-grab grabs a series' new episodes from now on, and turns off again", %{conn: conn} do
      TmdbStubs.stub_series_universe_for_targeting()

      body = conn |> put("/api/v1/titles/tv/246810/auto-grab") |> json_response(200)
      assert_schema(body, "TitleState")
      assert %{"auto_grab" => true} = body

      MediaCentaur.JobRuns.run_enqueued_jobs()
      assert MediaCentaur.Watchlist.caught_up(246_810, :tv_series) == {2, 1}
      assert Plans.list_drafts() == []

      assert %{"auto_grab" => false} =
               conn |> delete("/api/v1/titles/tv/246810/auto-grab") |> json_response(200)

      assert MediaCentaur.Watchlist.rung(246_810, :tv_series) == :follow
    end

    test "auto-grab for a title TMDB does not have is not found", %{conn: conn} do
      Req.Test.stub(:tmdb, fn conn -> Plug.Conn.send_resp(conn, 404, "{}") end)

      assert %{"error" => %{"code" => "not_found"}} =
               conn |> put("/api/v1/titles/movie/999/auto-grab") |> json_response(404)
    end

    test "unknown values are refused", %{conn: conn} do
      for attrs <- [
            %{approval_policy: "sometimes"},
            %{media_type: "book"},
            %{tmdb_id: "abc"},
            %{scope: "all"}
          ] do
        body = Map.merge(%{tmdb_id: 246_813, media_type: "movie"}, attrs)

        assert %{"error" => %{"code" => "invalid_request"}} =
                 conn |> json_post("/api/v1/plans", body) |> json_response(400)
      end
    end
  end

  describe "pursuits" do
    setup do
      :ok = ProwlarrStubs.mark_ready!()
    end

    test "lists in-flight pursuits by default", %{conn: conn} do
      pursuit = create_pursuit(%{title: "Sample Movie"})

      body = conn |> get("/api/v1/pursuits") |> json_response(200)

      assert_schema(body, "PursuitList")
      assert [%{"id" => id, "title" => "Sample Movie", "state" => "active"}] = body["pursuits"]
      assert id == pursuit.id
    end

    test "filters by outcome", %{conn: conn} do
      create_pursuit(%{title: "Sample Movie"})

      assert %{"pursuits" => []} =
               conn |> get("/api/v1/pursuits", state: "succeeded") |> json_response(200)

      assert %{"error" => %{"code" => "invalid_request"}} =
               conn |> get("/api/v1/pursuits", state: "x") |> json_response(400)

      assert %{"error" => %{"code" => "invalid_request"}} =
               conn |> get("/api/v1/pursuits", limit: "0") |> json_response(400)
    end

    test "reads one pursuit with its units", %{conn: conn} do
      pursuit = create_pursuit(%{title: "Sample Movie"})

      body = conn |> get("/api/v1/pursuits/#{pursuit.id}") |> json_response(200)

      assert_schema(body, "PursuitDetail")
      assert %{"id" => id, "units" => [%{"state" => "active"}]} = body
      assert id == pursuit.id
    end

    test "a pursuit's detail says whether it waits for a person, and its progress", %{conn: conn} do
      pursuit = create_pursuit(%{title: "Sample Movie", awaiting_decision_at: DateTime.utc_now(:second)})

      body = conn |> get("/api/v1/pursuits/#{pursuit.id}") |> json_response(200)

      assert_schema(body, "PursuitDetail")
      assert %{"awaiting_decision" => true, "units_wanted" => 1, "units_satisfied" => 0} = body
    end

    test "another release can be listed and chosen for a pursuit", %{conn: conn} do
      Req.Test.stub(:prowlarr, fn conn ->
        case conn.method do
          "POST" -> Req.Test.json(conn, %{})
          _search -> Req.Test.json(conn, [film_release()])
        end
      end)

      pursuit =
        create_pursuit(%{
          tmdb_id: "246813",
          tmdb_type: "movie",
          title: "Sample Movie",
          year: 2005,
          awaiting_decision_at: DateTime.utc_now(:second)
        })

      body = conn |> get("/api/v1/pursuits/#{pursuit.id}/alternatives") |> json_response(200)
      assert_schema(body, "ReleaseList")
      assert %{"releases" => [%{"guid" => "film"}]} = body

      chosen =
        conn
        |> json_post("/api/v1/pursuits/#{pursuit.id}/alternatives", %{guid: "film"})
        |> json_response(200)

      assert_schema(chosen, "PursuitDetail")
      assert %{"awaiting_decision" => false} = chosen

      assert %{"error" => %{"code" => "release_unavailable"}} =
               conn
               |> json_post("/api/v1/pursuits/#{pursuit.id}/alternatives", %{guid: "unknown"})
               |> json_response(404)
    end

    test "an unknown or malformed pursuit id is 404", %{conn: conn} do
      assert conn |> get("/api/v1/pursuits/not-a-uuid") |> json_response(404)
      assert conn |> post("/api/v1/pursuits/not-a-uuid/cancel") |> json_response(404)
      assert conn |> post("/api/v1/pursuits/not-a-uuid/search-again") |> json_response(404)
    end

    test "cancelling closes it, and a second cancel is a conflict", %{conn: conn} do
      pursuit = create_pursuit(%{title: "Sample Movie"})

      assert %{"state" => "cancelled"} =
               conn
               |> post("/api/v1/pursuits/#{pursuit.id}/cancel")
               |> json_response(200)
               |> assert_schema("PursuitSummary")

      assert %{"error" => %{"code" => "not_cancellable"}} =
               conn |> post("/api/v1/pursuits/#{pursuit.id}/cancel") |> json_response(409)
    end

    test "search again starts a new plan for what did not land", %{conn: conn} do
      pursuit =
        create_pursuit(%{
          title: "Sample Movie",
          tmdb_id: "246813",
          tmdb_type: "movie",
          state: "exhausted"
        })

      body =
        conn
        |> json_post("/api/v1/pursuits/#{pursuit.id}/search-again", %{approval_policy: "automatic"})
        |> json_response(202)

      assert_schema(body, "Plan")
      assert {:ok, %{approval_policy: "automatic"}} = Plans.fetch(body["id"])
    end
  end

  describe "queue" do
    test "reads the download client's queue", %{conn: conn} do
      body = conn |> get("/api/v1/queue") |> json_response(200)

      assert_schema(body, "Queue")
      assert is_list(body["items"])
    end

    test "cancelling with no client configured says so", %{conn: conn} do
      assert %{"error" => %{"code" => "not_configured"}} =
               conn |> delete("/api/v1/queue/#{String.duplicate("a", 40)}") |> json_response(503)
    end
  end
end
