defmodule MediaCentaur.Acquisition.Reactor.HandlersTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.{PlanEvents, Plans}
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
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
  defp below_floor_movie, do: [release("Sample.Movie.2005.720p.WEB-DL", "movie-720p", 20)]

  defp gate(plan) do
    {:ok, plan} = Plans.fetch(plan.id)
    Handlers.plan_changed(%PlanEvents.Changed{plan_id: plan.id, status: plan.status})
    {:ok, reloaded} = Plans.fetch(plan.id)
    reloaded
  end

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
      # test is about the Reactor's own dispatch, so it runs one.
      start_supervised!(MediaCentaur.Acquisition.Reactor)

      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      Topics.subscribe(Topics.acquisition_updates())

      # Neither a hand-off's recovery nor Prowlarr going down plans anything.
      {:changed, _state} =
        IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})

      {:changed, _state} = IntegrationAvailability.report({:handoff, :usenet}, :up)
      refute_receive %PlanEvents.Changed{}, 200

      {:changed, :up} = IntegrationAvailability.report(:prowlarr, :up)

      assert_receive %PlanEvents.Changed{}, 2_000
    end
  end

  describe "plan_changed/1 — manual plans" do
    test "automatic + clean commits one pursuit" do
      stub_search(acceptable_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      committed = gate(plan)

      assert committed.status == "committed"
      assert [%Pursuit{origin: "manual"}] = Repo.all(Pursuit)
    end

    test "automatic + a gap stays ready" do
      stub_search([])
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert gate(plan).status == "ready"
      assert Repo.all(Pursuit) == []
    end

    test "automatic + only below-preference candidates stays ready" do
      stub_search(below_floor_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert gate(plan).status == "ready"
      assert Repo.all(Pursuit) == []
    end

    test "review never commits, even when clean" do
      stub_search(acceptable_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "review")

      assert gate(plan).status == "ready"
      assert Repo.all(Pursuit) == []
    end

    test "automatic + an approval rejection stays ready" do
      stub_search(acceptable_movie())
      # An active pursuit already claims the movie → CommitPlan rejects with overlap.
      create_pursuit(%{tmdb_id: "246813", tmdb_type: "movie", title: "Sample Movie", origin: "manual"})
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert gate(plan).status == "ready"
      assert length(Repo.all(Pursuit)) == 1
    end
  end

  describe "plan_changed/1 — tracking plans that found nothing" do
    # A tracking draft is the tick's scratch work: nothing found and
    # nothing to offer has no record value and is deleted (ADR-056 Q3).
    # An offer is different — it needs a person — so a draft carrying
    # one stays on the board whatever the policy (spec 2026-09-17
    # decision 7); before that it was deleted with the offer unseen.

    # Oban runs the search inline here, so an empty indexer leaves the
    # draft `ready` with its unit unfound and nothing offered. The offer,
    # when a case needs one, is forced on: proving that a pack-only
    # indexer produces it is `drop_planner_test`'s job.
    defp ready_tracking_draft(unit_attrs) do
      stub_search([])
      item = create_tracking_item(%{name: "Sample Show"})

      {:ok, plan} =
        Plans.create_tracking_plan(
          %{
            identity: MediaCentaur.ReleaseTracking.Identity.for_item(item),
            tracking_item_id: item.id,
            approval_policy: "automatic",
            criteria: %{"min_quality" => "hd_1080p", "max_quality" => "uhd_4k"}
          },
          [%{season_number: 1, episode_number: 13, label: "S01E13", position: 0}]
        )

      {:ok, ready} = Plans.fetch(plan.id)
      assert ready.status == "ready"

      [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"
      if unit_attrs != [], do: force_attrs(unit, unit_attrs)

      ready
    end

    test "nothing found and nothing offered deletes the draft" do
      plan = ready_tracking_draft([])

      Handlers.plan_changed(%PlanEvents.Changed{plan_id: plan.id, status: "ready"})

      assert Plans.fetch(plan.id) == {:error, :not_found}
    end

    test "nothing found but a pack offered keeps the draft ready for a person, even under automatic" do
      plan =
        ready_tracking_draft(
          offered_guid: "pack-s1",
          offered_title: "Sample.Show.S01.COMPLETE.1080p.WEB-DL"
        )

      Handlers.plan_changed(%PlanEvents.Changed{plan_id: plan.id, status: "ready"})

      assert {:ok, %Plans.Plan{status: "ready"}} = Plans.fetch(plan.id)
      assert Repo.all(Pursuit) == []
    end
  end

  describe "clean?/1" do
    test "true only when every non-excluded unit is found" do
      stub_search(acceptable_movie())
      {:ok, found} = Plans.create_movie_plan(@movie)
      {:ok, found} = Plans.fetch(found.id)
      assert Plans.clean?(found)

      # A different title: the corpus is consult-first, so the same term
      # would answer from the first search's recorded result.
      stub_search([])
      {:ok, gap} = Plans.create_movie_plan(%{tmdb_id: "246814", title: "Sample Movie B", year: 2006})
      {:ok, gap} = Plans.fetch(gap.id)
      refute Plans.clean?(gap)
    end
  end
end
