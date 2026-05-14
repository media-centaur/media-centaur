defmodule MediaCentarr.Acquisition.Pursuits.Commands.ArmTest do
  use MediaCentarr.DataCase, async: false

  import Ecto.Query

  alias MediaCentarr.Acquisition.Pursuits.{Pursuit, Recipe}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Arm
  alias MediaCentarr.Acquisition.Target

  defp enqueued_pursue_target_jobs do
    Repo.all(from j in Oban.Job, where: j.worker == "MediaCentarr.Acquisition.Jobs.PursueTarget")
  end

  defp run(args) do
    Oban.Testing.with_testing_mode(:manual, fn -> Arm.execute(args) end)
  end

  describe "execute/1 — new pursuit" do
    test "creates a new pursuit + seeking target and enqueues PursueTarget" do
      assert {:ok, %Target{} = target} =
               run(%{
                 tmdb_id: "603",
                 tmdb_type: "movie",
                 title: "Sample Movie",
                 year: 2010
               })

      assert target.status == "seeking"
      assert is_binary(target.pursuit_id)

      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      assert pursuit.recipe_type == "tmdb"
      assert pursuit.tmdb_id == "603"
      assert pursuit.year == 2010
      assert pursuit.current_target_id == target.id

      [job] = enqueued_pursue_target_jobs()
      assert job.args["target_id"] == target.id
    end

    test "default origin is auto when not specified" do
      assert {:ok, %Target{}} =
               run(%{tmdb_id: "603", tmdb_type: "movie", title: "Sample Movie"})

      assert [%Pursuit{origin: "auto"}] = Repo.all(Pursuit)
    end
  end

  describe "execute/1 — idempotency" do
    test "second call on the same TMDB tuple returns the existing in-flight target" do
      {:ok, first} = run(%{tmdb_id: "603", tmdb_type: "movie", title: "Sample Movie"})

      assert {:ok, second} =
               run(%{tmdb_id: "603", tmdb_type: "movie", title: "Sample Movie"})

      assert second.id == first.id
      assert Repo.aggregate(Pursuit, :count) == 1
    end

    test "second call after the prior target failed creates a fresh seeking target" do
      {:ok, first} = run(%{tmdb_id: "603", tmdb_type: "movie", title: "Sample Movie"})

      first
      |> Target.failed_changeset("test_failure")
      |> Repo.update!()

      assert {:ok, second} =
               run(%{tmdb_id: "603", tmdb_type: "movie", title: "Sample Movie"})

      refute second.id == first.id
      assert second.status == "seeking"

      # Same pursuit, two targets.
      assert Repo.aggregate(Pursuit, :count) == 1
      assert Repo.aggregate(Target, :count) == 2
    end

    test "second call after success returns the succeeded target without re-arming" do
      {:ok, first} = run(%{tmdb_id: "603", tmdb_type: "movie", title: "Sample Movie"})

      first
      |> Target.succeeded_changeset()
      |> Repo.update!()

      assert {:ok, same} =
               run(%{tmdb_id: "603", tmdb_type: "movie", title: "Sample Movie"})

      assert same.id == first.id
      assert same.status == "succeeded"
      assert Repo.aggregate(Target, :count) == 1
    end
  end

  describe "execute/1 — TV recipe extras" do
    test "carries season + episode through to the pursuit recipe" do
      assert {:ok, target} =
               run(%{
                 tmdb_id: "1396",
                 tmdb_type: "tv",
                 title: "Sample Show",
                 season_number: 1,
                 episode_number: 3
               })

      pursuit = Repo.get!(Pursuit, target.pursuit_id)
      recipe = Recipe.from(pursuit)
      assert recipe.season_number == 1
      assert recipe.episode_number == 3
    end
  end
end
