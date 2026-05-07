defmodule MediaCentarr.Acquisition.Pursuits.Commands.RecordUserChoiceTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.RecordUserChoice
  alias MediaCentarr.Acquisition.Pursuits.Events.{FallbackInitiated, UserDecisionRecorded}

  defp insert_pursuit_in_decision(tried \\ []) do
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
    |> Ecto.Changeset.change(state: "needs_decision", tried_release_guids: tried)
    |> Repo.update!()
  end

  describe "execute/1" do
    test "transitions needs_decision -> active, records both events, appends new guid to tried list" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      pursuit = insert_pursuit_in_decision(["old-guid"])

      assert {:ok, %Pursuit{} = updated} =
               RecordUserChoice.execute(%{
                 pursuit_id: pursuit.id,
                 chosen_guid: "new-guid",
                 choice_label: "Sample.Movie.2010.1080p.BluRay"
               })

      assert updated.state == "active"
      assert updated.attempt_count == 1
      assert updated.tried_release_guids == ["old-guid", "new-guid"]

      events = Enum.sort_by(Repo.all(Event), & &1.kind)
      kinds = Enum.map(events, & &1.kind)
      assert "fallback_initiated" in kinds
      assert "user_decision_recorded" in kinds

      assert_receive %UserDecisionRecorded{choice: "Sample.Movie.2010.1080p.BluRay"}
      assert_receive %FallbackInitiated{previous_guid: "old-guid", reason: "user_choice"}
    end

    test "rejects pursuit not in needs_decision" do
      pursuit = insert_pursuit_in_decision()

      pursuit
      |> Ecto.Changeset.change(state: "active")
      |> Repo.update!()

      assert {:error, %Ecto.Changeset{}} =
               RecordUserChoice.execute(%{
                 pursuit_id: pursuit.id,
                 chosen_guid: "x",
                 choice_label: "y"
               })
    end

    test "returns :not_found when pursuit is missing" do
      assert {:error, :not_found} =
               RecordUserChoice.execute(%{
                 pursuit_id: Ecto.UUID.generate(),
                 chosen_guid: "x",
                 choice_label: "y"
               })
    end

    test "no previous guid available — fallback_initiated event has nil previous_guid" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())
      pursuit = insert_pursuit_in_decision([])

      assert {:ok, _} =
               RecordUserChoice.execute(%{
                 pursuit_id: pursuit.id,
                 chosen_guid: "first-guid",
                 choice_label: "Some Release"
               })

      assert_receive %FallbackInitiated{previous_guid: nil}
    end
  end
end
