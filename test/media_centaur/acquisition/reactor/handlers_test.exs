defmodule MediaCentaur.Acquisition.Reactor.HandlersTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.{PlanEvents, Plans}
  alias MediaCentaur.Acquisition.Reactor.Handlers
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.ProwlarrStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Topics

  @movie %{tmdb_id: "246813", title: "Sample Movie", year: 2005}

  setup do
    # Configured *and* tested green: a plan run holds when Prowlarr is
    # unconfigured, so a half-configured fixture would snooze every test.
    :ok = ProwlarrStubs.mark_ready!()

    :ok
  end

  # Prowlarr answers every search with the given releases; indexer
  # health reads as unconfigured (not blind) so the corpus records.
  defp stub_search(releases) do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/indexer"} -> Req.Test.json(conn, [])
        {"GET", "/api/v1/indexerstatus"} -> Req.Test.json(conn, [])
        {"GET", "/api/v1/search"} -> Req.Test.json(conn, releases)
        {"POST", "/api/v1/search"} -> Req.Test.json(conn, %{"approved" => true})
        _other -> Req.Test.json(conn, %{})
      end
    end)
  end

  defp release(title, guid, seeders) do
    %{
      "title" => title,
      "guid" => guid,
      "indexerId" => 1,
      "indexer" => "indexer-a",
      "seeders" => seeders
    }
  end

  defp acceptable_movie, do: [release("Sample.Movie.2005.1080p.WEB-DL", "movie-1080p", 20)]

  describe "prowlarr_available/0" do
    # A tracked episode whose want came due while Prowlarr was unavailable:
    # the drop planner held every tick, so nothing planned it.
    defp tracked_episode_want do
      item =
        create_tracking_item(%{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show"})

      create_intent_for(item, :grab)

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -30),
        title: "Episode 1",
        season_number: 1,
        episode_number: 1,
        released: true
      })

      :ok = ReleaseTracking.sync_wants(item)
      item
    end

    test "plans the wants that came due while Prowlarr was down" do
      stub_search([release("Sample.Show.S01E01.1080p.WEB-DL", "ep-1080p", 30)])
      tracked_episode_want()

      assert :ok = Handlers.prowlarr_available()

      assert [_plan] = Repo.all(Plans.Plan)
    end

    test "the Reactor routes Prowlarr's recovery here, and nothing else" do
      stub_search([release("Sample.Show.S01E01.1080p.WEB-DL", "ep-1080p", 30)])
      tracked_episode_want()

      # PubSub listeners are not started in the test environment — this
      # test is about the Reactor's own dispatch, so it runs one. Not
      # supervised: a supervisor's shutdown kills it where it stands, and
      # `GenServer.stop/1` below instead waits for the tick it is running.
      {:ok, reactor} = MediaCentaur.Acquisition.Reactor.start_link([])

      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      Topics.subscribe(Topics.acquisition_updates())

      # Neither a hand-off's recovery nor Prowlarr going down plans anything.
      {:changed, _state} =
        IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})

      {:changed, _state} = IntegrationAvailability.report({:handoff, :usenet}, :up)
      refute_receive %PlanEvents.Changed{}, 200

      {:changed, :up} = IntegrationAvailability.report(:prowlarr, :up)

      assert_receive %PlanEvents.Changed{}, 2_000

      # The plan event fires mid-tick. A clean stop drains the mailbox and
      # waits for the running callback, so the Reactor's database work
      # never outlives this test's connection (ADR-049).
      :ok = GenServer.stop(reactor)
    end
  end

  describe "clean?/1" do
    test "true only when every non-excluded unit is found" do
      stub_search(acceptable_movie())
      {:ok, found} = Plans.create_movie_plan(@movie)
      MediaCentaur.JobRuns.run_enqueued_jobs()
      {:ok, found} = Plans.fetch(found.id)
      assert Plans.clean?(found)

      # A different title: the corpus is consult-first, so the same term
      # would answer from the first search's recorded result.
      stub_search([])
      {:ok, gap} = Plans.create_movie_plan(%{tmdb_id: "246814", title: "Sample Movie B", year: 2006})
      MediaCentaur.JobRuns.run_enqueued_jobs()
      {:ok, gap} = Plans.fetch(gap.id)
      refute Plans.clean?(gap)
    end
  end
end
