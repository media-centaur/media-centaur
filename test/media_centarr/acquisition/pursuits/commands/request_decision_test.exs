defmodule MediaCentarr.Acquisition.Pursuits.Commands.RequestDecisionTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.RequestDecision
  alias MediaCentarr.Acquisition.Pursuits.Events.UserDecisionRequested

  defp insert_active_pursuit do
    {:ok, pursuit} =
      Repo.insert(
        Pursuit.create_changeset(%{
          tmdb_id: "12345",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto"
        })
      )

    pursuit
  end

  describe "execute/1" do
    test "transitions active to needs_decision and records UserDecisionRequested event" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      pursuit = insert_active_pursuit()

      assert {:ok, %Pursuit{state: "needs_decision"}} =
               RequestDecision.execute(%{
                 pursuit_id: pursuit.id,
                 prompt: "Download stalled for 24+ hours"
               })

      [event] = Repo.all(Event)
      assert event.kind == "user_decision_requested"
      assert event.payload == %{"prompt" => "Download stalled for 24+ hours"}

      assert_receive %UserDecisionRequested{prompt: "Download stalled for 24+ hours"}
    end

    test "rejects transition from non-active state" do
      pursuit =
        insert_active_pursuit()
        |> Ecto.Changeset.change(state: "needs_decision")
        |> Repo.update!()

      assert {:error, %Ecto.Changeset{}} =
               RequestDecision.execute(%{pursuit_id: pursuit.id, prompt: "X"})
    end

    test "returns :not_found for missing pursuit" do
      assert {:error, :not_found} =
               RequestDecision.execute(%{pursuit_id: Ecto.UUID.generate(), prompt: "X"})
    end
  end
end
