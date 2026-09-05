defmodule MediaCentaur.Acquisition.Reactor.HandlersTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.{PlanEvents, Plans}
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.Reactor.Handlers

  @movie %{tmdb_id: "246813", title: "Sample Movie", year: 2005}

  setup do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

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
