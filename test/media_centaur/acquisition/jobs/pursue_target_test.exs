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
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.ProwlarrStubs

  setup do
    # Install a stub that crashes if invoked — any Prowlarr call is a
    # bug since the worker should early-exit before reaching the network.
    Req.Test.stub(:prowlarr, fn _conn -> flunk("Prowlarr must not be called") end)

    # The worker refuses to search an unconfigured Prowlarr. Configuration
    # is the durable half; `IntegrationAvailability` is the runtime half
    # these tests drive.
    :ok = ProwlarrStubs.mark_ready!()

    :ok
  end

  # Shared fixtures — two describes build the same seeking movie target
  # and drive the same Prowlarr stub.

  defp movie_release(title, guid, attrs) do
    Map.merge(
      %{"title" => title, "guid" => guid, "indexerId" => 1, "indexer" => "indexer-a"},
      Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    )
  end

  defp stub_grab_reply(reply) do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/indexer"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/indexerstatus"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/search"} ->
          Req.Test.json(conn, [
            movie_release("Sample.Movie.2005.1080p.WEB-DL.H.264-GRP", "only-copy", %{
              grabs: 40,
              protocol: "usenet"
            })
          ])

        {"POST", "/api/v1/search"} ->
          reply.(conn)

        # A hand-off that goes down enqueues the hand-off probe, which
        # Oban runs inline — these are the requests it makes. The
        # client Prowlarr could not hand the release to is still
        # configured and still failing its test.
        {"GET", "/api/v1/downloadclient"} ->
          Req.Test.json(conn, [
            %{
              "id" => 1,
              "name" => "Sample Usenet Client",
              "implementation" => "Sabnzbd",
              "protocol" => "usenet",
              "enable" => true,
              "fields" => [
                %{"name" => "host", "value" => "usenet.test"},
                %{"name" => "port", "value" => 8080}
              ]
            }
          ])

        {"POST", "/api/v1/downloadclient/testall"} ->
          Req.Test.json(conn, [%{"id" => 1, "isValid" => false}])
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

  describe "the attempt cap is the Settings value, not a constant" do
    # Settings → Acquisition has carried a "max attempts" stepper
    # (`AutoGrabSettings.max_attempts`, 1–50) that the worker never read:
    # it exhausted at a hard-coded twelve whatever the person set.

    test "a target exhausts at the configured number of attempts" do
      :ok = MediaCentaur.Acquisition.AutoGrabSettings.put(:max_attempts, 1)

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} -> Req.Test.json(conn, [])
          _other -> Req.Test.json(conn, [])
        end
      end)

      {_pursuit, target} =
        create_pursuit_with_target(%{
          state: "seeking",
          status: "seeking",
          title: "Sample Movie",
          year: 2005
        })

      assert :ok = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.status == "failed"
      assert reloaded.attempt_count == 1
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

    defp download_client_unavailable(conn) do
      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.json(%{
        "description" =>
          "NzbDrone.Core.Download.Clients.DownloadClientUnavailableException: Unable to connect to SABnzbd"
      })
    end

    test "a 5xx from grab keeps the attempt count and snoozes at the cadence under download_client_unavailable" do
      stub_grab_reply(&download_client_unavailable/1)
      target = seeking_movie_target()

      assert {:snooze, 60} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.attempt_count == 0
      assert reloaded.last_attempt_outcome == "download_client_unavailable"
      assert reloaded.status == "seeking"
      assert %DateTime{} = reloaded.next_attempt_at

      # The grab that discovered the outage is also what put the hand-off
      # down, so the next wake is held rather than discovering it again.
      refute IntegrationAvailability.up?({:handoff, :usenet})
    end

    test "a transport error from grab is the same outage" do
      stub_grab_reply(&Req.Test.transport_error(&1, :econnrefused))
      target = seeking_movie_target()

      assert {:snooze, _seconds} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.attempt_count == 0
      assert reloaded.last_attempt_outcome == "download_client_unavailable"
    end

    test "a 5xx that is not the hand-off exception charges an attempt and snoozes on the ladder" do
      stub_grab_reply(fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{
          "description" => "NzbDrone.Core.Exceptions.ReleaseUnavailableException: gone"
        })
      end)

      target = seeking_movie_target()

      assert {:snooze, seconds} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      assert seconds == 4 * 60 * 60

      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.attempt_count == target.attempt_count + 1
      assert reloaded.last_attempt_outcome == "grab_failed"
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

  describe "the attempt that would exhaust asks about a pack first" do
    # F5 (spec 2026-09-17): the retry loop only ever searched the episode
    # term, so an episode that survives only inside a season pack was
    # invisible to it — twelve attempts over a week, then a silent
    # exhaustion. Before giving up, the worker runs the wider terms once
    # and, when a pack contains the episode, asks instead of exhausting.

    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()

      {pursuit, target} =
        create_pursuit_with_target(%{
          tmdb_id: "500",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 3,
          state: "seeking",
          status: "seeking",
          attempt_count: 11
        })

      %{pursuit: pursuit, target: target}
    end

    defp stub_indexer(results_by_query) do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/search"} ->
            %{"query" => query} = URI.decode_query(conn.query_string)
            Req.Test.json(conn, Map.get(results_by_query, query, []))
        end
      end)
    end

    defp season_pack do
      %{
        "title" => "Sample.Show.S01.1080p.WEB-DL",
        "guid" => "pack-s01",
        "indexerId" => 1,
        "indexer" => "indexer-a",
        "size" => 20_000_000_000,
        "grabs" => 40,
        "publishDate" => "2026-04-01T00:00:00Z"
      }
    end

    test "a pack-only indexer turns the exhausting attempt into a decision", %{
      pursuit: pursuit,
      target: target
    } do
      stub_indexer(%{"Sample Show S01E03" => [], "Sample Show S01" => [season_pack()]})

      assert {:ok, :needs_decision} =
               PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      assert MediaCentaur.Repo.reload!(target).status == "seeking"

      assert %{awaiting_decision_at: %DateTime{}} =
               MediaCentaur.Acquisition.Pursuits.Units.lead(pursuit.id)

      assert [
               %{
                 payload: %{
                   "prompt" => "Only a pack has this episode. Picking it downloads the whole pack."
                 }
               }
             ] =
               pursuit.id
               |> MediaCentaur.Acquisition.Pursuits.events_for()
               |> Enum.filter(&(&1.kind == "user_decision_requested"))
    end

    test "with nothing covering the episode it exhausts as before", %{target: target} do
      stub_indexer(%{})

      assert :ok = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      assert MediaCentaur.Repo.reload!(target).status == "failed"
    end
  end

  describe "held work — a known-down integration is not asked" do
    # Rollout step 1 of the availability design: a pursuit never spends a
    # Prowlarr search or a grab while the integration it needs is known
    # down. It is held — no request, no attempt, no stamp — and asks
    # again at the probe cadence.

    test "Prowlarr down: no search, no grab, no attempt charged, snoozed at the probe cadence" do
      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      target = seeking_movie_target()
      Req.Test.stub(:prowlarr, fn _conn -> flunk("Prowlarr must not be called while down") end)

      assert {:snooze, 60} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.attempt_count == target.attempt_count
      assert reloaded.last_attempt_outcome == target.last_attempt_outcome
      assert reloaded.next_attempt_at == target.next_attempt_at
    end

    test "hand-off down for the release's protocol: the search runs from the corpus, the grab does not" do
      {:changed, _state} =
        IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})

      target = seeking_movie_target()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            Req.Test.json(conn, [
              movie_release("Sample.Movie.2005.1080p.WEB-DL.H.264-GRP", "only-copy", %{
                grabs: 40,
                protocol: "usenet"
              })
            ])

          {"POST", "/api/v1/search"} ->
            flunk("no grab while the hand-off is down")

          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])
        end
      end)

      assert {:snooze, 60} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      # A hand-off hold is per-pursuit — only a release on the broken
      # protocol is held — so it is recorded on the target, which is
      # what the Waiting copy reads. No attempt is charged.
      reloaded = MediaCentaur.Repo.reload!(target)
      assert reloaded.attempt_count == target.attempt_count
      assert reloaded.last_attempt_outcome == "download_client_unavailable"
      assert %DateTime{} = reloaded.next_attempt_at
    end

    test "a second held run leaves the scheduled next attempt alone" do
      {:changed, _state} =
        IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})

      target = seeking_movie_target()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            Req.Test.json(conn, [
              movie_release("Sample.Movie.2005.1080p.WEB-DL.H.264-GRP", "only-copy", %{
                grabs: 40,
                protocol: "usenet"
              })
            ])

          {"GET", "/api/v1/indexer"} ->
            Req.Test.json(conn, [])

          {"GET", "/api/v1/indexerstatus"} ->
            Req.Test.json(conn, [])
        end
      end)

      assert {:snooze, 60} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      first = MediaCentaur.Repo.reload!(target)

      assert {:snooze, 60} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      second = MediaCentaur.Repo.reload!(target)

      assert second.next_attempt_at == first.next_attempt_at
      assert second.last_attempt_at == first.last_attempt_at
      assert second.attempt_count == target.attempt_count
    end
  end
end
