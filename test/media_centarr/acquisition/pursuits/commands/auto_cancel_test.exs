defmodule MediaCentarr.Acquisition.Pursuits.Commands.AutoCancelTest do
  use MediaCentarr.DataCase, async: false

  import Ecto.Query
  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.AutoCancel
  alias MediaCentarr.Acquisition.Pursuits.Events.AutoCancelled
  alias MediaCentarr.Acquisition.Target

  defp enqueued_pursue_target_jobs do
    Repo.all(from j in Oban.Job, where: j.worker == "MediaCentarr.Acquisition.Jobs.PursueTarget")
  end

  defp run(args) do
    Oban.Testing.with_testing_mode(:manual, fn -> AutoCancel.execute(args) end)
  end

  describe "execute/1 — auto-pivot to fresh search" do
    test "cancels the current target and inserts a fresh seeking target on the same pursuit" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())

      {pursuit, current_target} =
        create_pursuit_with_target(%{
          status: "acquired",
          release_title: "Sample.Show.S01E01.x264",
          prowlarr_guid: "dead-release-1"
        })

      assert {:ok, %Pursuit{} = pivoted} =
               run(%{pursuit_id: pursuit.id, reason: :zero_seeders})

      # Pursuit stays active and points at a new target.
      assert pivoted.state == "active"
      refute pivoted.current_target_id == current_target.id
      refute is_nil(pivoted.current_target_id)

      # Previous target is now terminal with the auto-cancel reason.
      old_target = Repo.get!(Target, current_target.id)
      assert old_target.status == "cancelled"
      assert old_target.cancelled_reason == "zero_seeders"

      # New target is seeking.
      new_target = Repo.get!(Target, pivoted.current_target_id)
      assert new_target.status == "seeking"
      assert new_target.pursuit_id == pursuit.id

      # The dead release's guid is on tried_release_guids so the next
      # search won't re-pick it.
      assert "dead-release-1" in pivoted.tried_release_guids

      # The receive order doesn't matter; both events fired.
      assert_receive %AutoCancelled{reason: "zero_seeders"}
    end

    test "records auto_cancelled and target_changed events in that order" do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          status: "acquired",
          release_title: "Sample.Show.S01E01",
          prowlarr_guid: "guid-x"
        })

      assert {:ok, _pivoted} = run(%{pursuit_id: pursuit.id, reason: :zero_seeders})

      kinds =
        Event
        |> where([e], e.pursuit_id == ^pursuit.id)
        |> order_by([e], asc: e.occurred_at, asc: e.inserted_at)
        |> Repo.all()
        |> Enum.map(& &1.kind)

      assert kinds == ["auto_cancelled", "target_changed"]
    end

    test "enqueues a PursueTarget Oban job for the new target" do
      {pursuit, _target} = create_pursuit_with_target(%{status: "acquired", prowlarr_guid: "g1"})

      assert {:ok, pivoted} = run(%{pursuit_id: pursuit.id, reason: :zero_seeders})

      [job] = enqueued_pursue_target_jobs()
      assert job.args["target_id"] == pivoted.current_target_id
      assert job.queue == "acquisition"
    end
  end

  describe "execute/1 — no current target" do
    test "records auto_cancelled, does not create a new target, does not enqueue" do
      pursuit = create_pursuit()

      assert {:ok, %Pursuit{state: "active", current_target_id: nil}} =
               run(%{pursuit_id: pursuit.id, reason: :zero_seeders})

      assert [%{kind: "auto_cancelled"}] = Repo.all(Event)
      assert [] = enqueued_pursue_target_jobs()
    end
  end

  describe "execute/1 — error cases" do
    test "returns :not_found for missing pursuit" do
      assert {:error, :not_found} =
               run(%{pursuit_id: Ecto.UUID.generate(), reason: :zero_seeders})
    end
  end
end
