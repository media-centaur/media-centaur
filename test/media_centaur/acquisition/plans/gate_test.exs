defmodule MediaCentaur.Acquisition.Plans.GateTest do
  use MediaCentaur.DataCase, async: false
  use Oban.Testing, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Jobs.{GatePlan, RunPlan}
  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.JobRuns
  alias MediaCentaur.ProwlarrStubs

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

  # Solves the plan — RunPlan alone — and returns what the solve inserted.
  # The gate it enqueues is left waiting, so a test can shape the ready
  # plan before the gate reads it.
  defp solve(plan) do
    {_result, inserts} =
      JobRuns.capture_inserts(fn ->
        perform_job(RunPlan, %{"plan_id" => plan.id})
      end)

    inserts
  end

  defp gate_inserts(inserts), do: Enum.filter(inserts, &(&1.worker == inspect(GatePlan)))

  # Runs what is enqueued — the solve, then the gate it inserted — and
  # reads the plan back.
  defp solve_and_gate(plan) do
    JobRuns.run_enqueued_jobs()
    Plans.fetch(plan.id)
  end

  describe "the gate is owed with the ready transition (ADR-077, rule 1)" do
    # Regression: the gate rode a PlanEvents.Changed PubSub message to the
    # Reactor; a lost message left an automatic plan on the board, and a
    # tracking draft blocking its want, for good.
    test "a gated plan's solve inserts GatePlan inside the ready transition" do
      stub_search(acceptable_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert [%{in_transaction?: true, args: %{"plan_id" => plan_id}}] =
               plan |> solve() |> gate_inserts()

      assert plan_id == plan.id
    end

    test "a crashed solve — ready with an error — is gated too" do
      Req.Test.stub(:prowlarr, fn conn ->
        Req.Test.json(conn, [%{"title" => 123, "guid" => "garbage", "indexerId" => 1}])
      end)

      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert [%{in_transaction?: true}] = plan |> solve() |> gate_inserts()
      assert {:ok, %{status: "ready", error: "planning crashed" <> _}} = Plans.fetch(plan.id)
    end

    test "a review plan is not gated" do
      stub_search(acceptable_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "review")

      assert [] = plan |> solve() |> gate_inserts()
    end
  end

  describe "manual plans" do
    test "automatic + clean commits one pursuit" do
      stub_search(acceptable_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert {:ok, %{status: "committed"}} = solve_and_gate(plan)
      assert [%Pursuit{origin: "manual"}] = Repo.all(Pursuit)
    end

    test "automatic + a gap stays ready" do
      stub_search([])
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert {:ok, %{status: "ready"}} = solve_and_gate(plan)
      assert Repo.all(Pursuit) == []
    end

    test "automatic + only below-preference candidates stays ready" do
      stub_search(below_floor_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert {:ok, %{status: "ready"}} = solve_and_gate(plan)
      assert Repo.all(Pursuit) == []
    end

    test "review never commits, even when clean" do
      stub_search(acceptable_movie())
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "review")

      assert {:ok, %{status: "ready"}} = solve_and_gate(plan)
      assert Repo.all(Pursuit) == []
    end

    test "automatic + an approval rejection stays ready" do
      stub_search(acceptable_movie())
      # An active pursuit already claims the movie → CommitPlan rejects with overlap.
      create_pursuit(%{tmdb_id: "246813", tmdb_type: "movie", title: "Sample Movie", origin: "manual"})
      {:ok, plan} = Plans.create_movie_plan(@movie, approval_policy: "automatic")

      assert {:ok, %{status: "ready"}} = solve_and_gate(plan)
      assert length(Repo.all(Pursuit)) == 1
    end
  end

  describe "tracking plans that found nothing" do
    # A tracking draft is the tick's scratch work: nothing found and
    # nothing to offer has no record value and is deleted (ADR-056 Q3).
    # An offer is different — it needs a person — so a draft carrying
    # one stays on the board whatever the policy (spec 2026-09-17
    # decision 7); before that it was deleted with the offer unseen.

    # An empty indexer leaves the draft `ready` with its unit unfound and
    # nothing offered. The offer, when a case needs one, is forced on
    # before the gate runs: proving that a pack-only indexer produces it
    # is `drop_planner_test`'s job.
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

      solve(plan)

      {:ok, ready} = Plans.fetch(plan.id)
      assert ready.status == "ready"

      [unit] = Plans.units_for(plan.id)
      assert unit.status == "unfound"
      if unit_attrs != [], do: force_attrs(unit, unit_attrs)

      ready
    end

    test "nothing found and nothing offered deletes the draft" do
      plan = ready_tracking_draft([])

      assert {:error, :not_found} = solve_and_gate(plan)
    end

    test "nothing found but a pack offered keeps the draft ready for a person, even under automatic" do
      plan =
        ready_tracking_draft(
          offered_guid: "pack-s1",
          offered_title: "Sample.Show.S01.COMPLETE.1080p.WEB-DL"
        )

      assert {:ok, %Plans.Plan{status: "ready"}} = solve_and_gate(plan)
      assert Repo.all(Pursuit) == []
    end
  end
end
