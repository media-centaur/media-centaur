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
    # Same defect as the plan runner's movie terms, on the unattended
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

  describe "grab failure — an unreachable download client is an outage, not a bad release" do
    # Evidence run 2026-09-17: Prowlarr found the right release in two
    # seconds, then answered the grab with HTTP 500
    # DownloadClientUnavailableException because SABnzbd was down. The
    # worker charged that to the release — attempt consumed, four-hour
    # snooze — and the modal asked the user to pick an alternative.
    # Search errors already snooze without charging an attempt; grab
    # errors from the infrastructure must do the same.

    defp stub_grab_reply(reply) do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            Req.Test.json(conn, [
              movie_release("Sample.Movie.2005.1080p.WEB-DL.H.264-GRP", "only-copy", %{grabs: 40})
            ])

          {"POST", "/api/v1/search"} ->
            reply.(conn)
        end
      end)
    end

    defp seeking_movie_target do
      {_pursuit, target} =
        create_pursuit_with_target(%{
          state: "seeking",
          status: "seeking",
          title: "Sample Movie",
          year: 2005
        })

      target
    end

    defp download_client_unavailable(conn) do
      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.json(%{
        "description" =>
          "NzbDrone.Core.Download.Clients.DownloadClientUnavailableException: Unable to connect to SABnzbd"
      })
    end

    test "a 5xx from grab keeps the attempt count and snoozes briefly under download_client_unavailable" do
      stub_grab_reply(&download_client_unavailable/1)
      target = seeking_movie_target()

      assert {:snooze, seconds} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      assert seconds < 60 * 60

      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.attempt_count == 0
      assert reloaded.last_attempt_outcome == "download_client_unavailable"
      assert reloaded.status == "seeking"
      assert %DateTime{} = reloaded.next_attempt_at
    end

    test "a transport error from grab is the same outage" do
      stub_grab_reply(&Req.Test.transport_error(&1, :econnrefused))
      target = seeking_movie_target()

      assert {:snooze, _seconds} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.attempt_count == 0
      assert reloaded.last_attempt_outcome == "download_client_unavailable"
    end

    test "a 4xx from grab still charges the release" do
      stub_grab_reply(fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"message" => "guid not found"})
      end)

      target = seeking_movie_target()

      assert {:snooze, _seconds} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.attempt_count == 1
      assert reloaded.last_attempt_outcome == "grab_failed"
    end
  end
end
