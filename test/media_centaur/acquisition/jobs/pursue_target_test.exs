defmodule MediaCentaur.Acquisition.Jobs.PursueTargetTest do
  @moduledoc """
  Defensive checks on the worker that should NEVER reach Prowlarr.

  The architectural primary defense is that `Satisfy` / `Exhaust` /
  `Cancel` cancel in-flight targets at terminal-pursuit transition, so
  the worker's next wake sees a cancelled target and early-exits via the
  pre-existing target-status guard. This test asserts the second layer:
  even if a `seeking` target row somehow survives on a terminal pursuit
  (race, manual DB edit, code path that bypasses the cleanup), the worker
  must not call Prowlarr — pursuit state is the authority.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Jobs.PursueTarget

  setup do
    # Install a stub that crashes if invoked — any Prowlarr call is a
    # bug since the worker should early-exit before reaching the network.
    Req.Test.stub(:prowlarr, fn _conn -> flunk("Prowlarr must not be called") end)

    :ok
  end

  describe "perform/1 — pursuit-state guard" do
    for terminal_state <- ["satisfied", "exhausted", "cancelled"] do
      test "early-exits for #{terminal_state} pursuit even when target is seeking" do
        {_pursuit, target} =
          create_pursuit_with_target(%{state: unquote(terminal_state), status: "seeking"})

        assert {:ok, :pursuit_terminal} =
                 PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      end
    end
  end

  describe "movie search — best of every query, not the first that hits" do
    # Same defect as the plan runner's movie ladder, on the unattended
    # path: the movie queries are alternate phrasings of ONE want, so
    # halting on the first that yields an acceptable release let the year
    # term decide the quality ceiling. Nobody clicks "Find more" on a
    # snooze-retry loop, so an auto-grabbed movie kept the worse copy
    # permanently.

    defp stub_movie_queries(results_by_query) do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)
            Req.Test.json(conn, Map.get(results_by_query, query, []))

          {"POST", "/api/v1/search"} ->
            Req.Test.json(conn, %{"approved" => true})
        end
      end)
    end

    defp movie_release(title, guid, attrs) do
      Map.merge(
        %{"title" => title, "guid" => guid, "indexerId" => 1, "indexer" => "indexer-a"},
        Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
      )
    end

    test "grabs the better release found behind the year-less query" do
      stub_movie_queries(%{
        "Sample Movie 2005" => [
          movie_release("Sample.Movie.2005.1080p.BluRay.H.264-GRP", "year-1080p", %{seeders: 40})
        ],
        "Sample Movie" => [
          movie_release(
            "Sample.Movie.2004.2160p.BluRay.REMUX.HEVC.DTS-HD.MA.5.1-GRP",
            "drift-4k",
            %{seeders: 3}
          )
        ]
      })

      {_pursuit, target} =
        create_pursuit_with_target(%{
          state: "seeking",
          status: "seeking",
          title: "Sample Movie",
          year: 2005
        })

      PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      assert MediaCentaur.Repo.reload!(target).prowlarr_guid == "drift-4k"
    end

    test "grabs break a tie when the indexer reports no seeders (usenet)" do
      stub_movie_queries(%{
        "Sample Movie 2005" => [],
        "Sample Movie" => [
          movie_release("Sample.Movie.2005.1080p.WEB-DL.H.264-LOW", "few-grabs", %{grabs: 12}),
          movie_release("Sample.Movie.2005.1080p.WEB-DL.H.264-HIGH", "many-grabs", %{grabs: 480})
        ]
      })

      {_pursuit, target} =
        create_pursuit_with_target(%{
          state: "seeking",
          status: "seeking",
          title: "Sample Movie",
          year: 2005
        })

      PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      assert MediaCentaur.Repo.reload!(target).prowlarr_guid == "many-grabs"
    end
  end
end
