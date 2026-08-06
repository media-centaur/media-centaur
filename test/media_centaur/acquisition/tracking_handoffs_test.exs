defmodule MediaCentaur.Acquisition.TrackingHandoffsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.Acquisition.Pursuits.Commands.Satisfy
  alias MediaCentaur.Acquisition.TrackingHandoffs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  defp stub_show(tmdb_id, name) do
    TmdbStubs.stub_routes([
      {"/tv/#{tmdb_id}",
       %{
         "id" => tmdb_id,
         "name" => name,
         "status" => "Returning Series",
         "number_of_seasons" => 1,
         "next_episode_to_air" => %{
           "air_date" => Date.to_iso8601(Date.add(Date.utc_today(), 7)),
           "season_number" => 1,
           "episode_number" => 9,
           "name" => "Next Week"
         }
       }}
    ])
  end

  # A committed plan + its pursuit, the post-approval shape the
  # handoffs read. The pursuit comes from the factory; the plan row is
  # stamped with its id the way CommitPlan does.
  defp create_committed_plan(pursuit, attrs) do
    {:ok, plan} =
      Repo.insert(
        Plan.create_changeset(
          Map.merge(
            %{
              tmdb_id: pursuit.tmdb_id,
              tmdb_type: pursuit.tmdb_type,
              title: pursuit.title
            },
            attrs
          )
        )
      )

    plan = force_attrs(plan, status: "committed", pursuit_id: pursuit.id)

    plan
  end

  describe "grab-future handoff (on completion)" do
    test "a satisfied pursuit from a grab_future plan starts tracking the title" do
      stub_show(42_001, "Sample Future Show")

      {pursuit, target} =
        create_pursuit_with_target(%{
          recipe_type: "tmdb",
          tmdb_id: "42001",
          tmdb_type: "tv",
          title: "Sample Future Show",
          season_number: 1,
          episode_number: 1,
          origin: "manual",
          status: "acquired"
        })

      create_committed_plan(pursuit, %{grab_future: true})

      {:ok, satisfied} =
        Satisfy.execute(%{
          pursuit_id: pursuit.id,
          final_target_id: target.id,
          final_release_title: "Sample.Future.Show.S01E01.1080p"
        })

      assert satisfied.state == "satisfied"

      item = ReleaseTracking.get_item_by_tmdb(42_001, :tv_series)
      assert item
      assert item.status == :watching
    end

    test "no handoff without the grab_future opt-in" do
      {pursuit, target} =
        create_pursuit_with_target(%{
          recipe_type: "tmdb",
          tmdb_id: "42002",
          tmdb_type: "tv",
          title: "Sample Plain Show",
          season_number: 1,
          episode_number: 1,
          origin: "manual",
          status: "acquired"
        })

      create_committed_plan(pursuit, %{grab_future: false})

      {:ok, _} =
        Satisfy.execute(%{
          pursuit_id: pursuit.id,
          final_target_id: target.id,
          final_release_title: "Sample.Plain.Show.S01E01.1080p"
        })

      refute ReleaseTracking.get_item_by_tmdb(42_002, :tv_series)
    end

    test "an already-tracked title is not duplicated" do
      stub_show(42_003, "Sample Tracked Show")

      existing =
        create_tracking_item(%{
          tmdb_id: 42_003,
          media_type: :tv_series,
          name: "Sample Tracked Show"
        })

      {pursuit, target} =
        create_pursuit_with_target(%{
          recipe_type: "tmdb",
          tmdb_id: "42003",
          tmdb_type: "tv",
          title: "Sample Tracked Show",
          season_number: 1,
          episode_number: 1,
          origin: "manual",
          status: "acquired"
        })

      create_committed_plan(pursuit, %{grab_future: true})

      {:ok, _} =
        Satisfy.execute(%{
          pursuit_id: pursuit.id,
          final_target_id: target.id,
          final_release_title: "Sample.Tracked.Show.S01E01.1080p"
        })

      item = ReleaseTracking.get_item_by_tmdb(42_003, :tv_series)
      assert item.id == existing.id
    end
  end

  describe "gap handoff (track what planning couldn't find)" do
    test "unfound units become gap-provenance wants on a (created) track" do
      stub_show(42_010, "Sample Gappy Show")

      {:ok, plan} =
        Repo.insert(
          Plan.create_changeset(%{
            tmdb_id: "42010",
            tmdb_type: "tv",
            title: "Sample Gappy Show"
          })
        )

      {:ok, plan} = Repo.update(Ecto.Changeset.change(plan, status: "ready"))

      for {episode, status} <- [{1, "found"}, {2, "unfound"}, {3, "unfound"}] do
        {:ok, unit} =
          Repo.insert(
            MediaCentaur.Acquisition.Plans.PlanUnit.create_changeset(%{
              plan_id: plan.id,
              season_number: 2,
              episode_number: episode,
              label: "S02E0#{episode}",
              position: episode
            })
          )

        {:ok, _} = Repo.update(Ecto.Changeset.change(unit, status: status))
      end

      assert {:ok, 2} = TrackingHandoffs.track_plan_gaps(plan.id)

      item = ReleaseTracking.get_item_by_tmdb(42_010, :tv_series)
      assert item

      wants = ReleaseTracking.open_wants_for_item(item.id)
      assert length(wants) == 2
      assert Enum.all?(wants, &(&1.provenance == :gap))
      assert Enum.map(wants, & &1.episode_number) == [2, 3]
    end

    test "gap wants are idempotent against an existing track's ledger" do
      stub_show(42_011, "Sample Regappy Show")

      {:ok, plan} =
        Repo.insert(
          Plan.create_changeset(%{
            tmdb_id: "42011",
            tmdb_type: "tv",
            title: "Sample Regappy Show"
          })
        )

      {:ok, plan} = Repo.update(Ecto.Changeset.change(plan, status: "ready"))

      {:ok, unit} =
        Repo.insert(
          MediaCentaur.Acquisition.Plans.PlanUnit.create_changeset(%{
            plan_id: plan.id,
            season_number: 1,
            episode_number: 5,
            label: "S01E05",
            position: 0
          })
        )

      {:ok, _} = Repo.update(Ecto.Changeset.change(unit, status: "unfound"))

      assert {:ok, 1} = TrackingHandoffs.track_plan_gaps(plan.id)
      assert {:ok, 0} = TrackingHandoffs.track_plan_gaps(plan.id)

      item = ReleaseTracking.get_item_by_tmdb(42_011, :tv_series)
      assert [_only_one] = ReleaseTracking.open_wants_for_item(item.id)
    end
  end
end
