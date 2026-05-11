defmodule MediaCentarr.Acquisition.Pursuits.Commands.AutoCancelTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.AutoCancel
  alias MediaCentarr.Acquisition.Pursuits.Events.AutoCancelled
  alias MediaCentarr.Acquisition.Target

  describe "execute/1" do
    test "cancels the active target linked to the pursuit and records auto_cancelled event" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())

      {pursuit, target} = create_pursuit_with_target()

      assert {:ok, %Pursuit{} = same_pursuit} =
               AutoCancel.execute(%{pursuit_id: pursuit.id, reason: :zero_seeders})

      # Pursuit remains active — auto-cancel does not transition state in v1.
      assert same_pursuit.id == pursuit.id
      assert same_pursuit.state == "active"

      cancelled_target = Repo.get!(Target, target.id)
      assert cancelled_target.status == "cancelled"
      assert cancelled_target.cancelled_reason == "zero_seeders"

      [event] = Repo.all(Event)
      assert event.kind == "auto_cancelled"
      assert event.payload == %{"reason" => "zero_seeders"}

      assert_receive %AutoCancelled{}
    end

    test "no-op when no active target exists for the pursuit" do
      pursuit = create_pursuit()

      assert {:ok, %Pursuit{state: "active"}} =
               AutoCancel.execute(%{pursuit_id: pursuit.id, reason: :zero_seeders})

      # Event still recorded — explanation in the timeline matters even when
      # there's nothing to cancel mechanically.
      [event] = Repo.all(Event)
      assert event.kind == "auto_cancelled"
    end

    test "returns :not_found for missing pursuit" do
      assert {:error, :not_found} =
               AutoCancel.execute(%{pursuit_id: Ecto.UUID.generate(), reason: :zero_seeders})
    end
  end
end
