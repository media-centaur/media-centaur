defmodule MediaCentaur.Acquisition.Pursuits.Commands.RequestDecisionTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Pursuits.{Event, Pursuit, Unit, Units}
  alias MediaCentaur.Acquisition.Pursuits.Commands.RequestDecision
  alias MediaCentaur.Acquisition.Pursuits.Events.UserDecisionRequested
  alias MediaCentaur.TestFactory

  describe "execute/1" do
    test "sets the unit's awaiting_decision_at and records UserDecisionRequested event" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.acquisition_updates())
      pursuit = TestFactory.create_pursuit()

      assert {:ok, %Pursuit{state: "active"}} =
               RequestDecision.execute(%{
                 pursuit_id: pursuit.id,
                 prompt: "Download stalled for 24+ hours"
               })

      assert %Unit{awaiting_decision_at: %DateTime{}} = Units.single!(pursuit.id)

      [event] = Repo.all(Event)
      assert event.kind == "user_decision_requested"
      assert event.payload == %{"prompt" => "Download stalled for 24+ hours"}

      assert_receive %UserDecisionRequested{prompt: "Download stalled for 24+ hours"}
    end

    test "idempotent — re-issuing on an already-awaiting unit is a no-op (no event)" do
      original_ts = DateTime.add(DateTime.utc_now(:second), -3600, :second)
      pursuit = TestFactory.create_pursuit(%{awaiting_decision_at: original_ts})

      assert {:ok, %Pursuit{id: id}} =
               RequestDecision.execute(%{pursuit_id: pursuit.id, prompt: "X"})

      assert id == pursuit.id
      assert %Unit{awaiting_decision_at: ^original_ts} = Units.single!(pursuit.id)
      # No new event recorded — idempotent path returns early.
      assert Repo.aggregate(Event, :count) == 0
    end

    test "returns :not_found for missing pursuit" do
      assert {:error, :not_found} =
               RequestDecision.execute(%{pursuit_id: Ecto.UUID.generate(), prompt: "X"})
    end
  end
end
