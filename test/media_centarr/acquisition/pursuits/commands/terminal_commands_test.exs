defmodule MediaCentarr.Acquisition.Pursuits.Commands.TerminalCommandsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.{Cancel, Exhaust, Satisfy}

  alias MediaCentarr.Acquisition.Pursuits.Events.{
    PursuitCancelled,
    PursuitExhausted,
    PursuitSatisfied
  }

  alias MediaCentarr.Topics

  defp insert_active_pursuit(state \\ "active") do
    {:ok, pursuit} =
      Repo.insert(
        Pursuit.create_changeset(%{
          tmdb_id: "12345",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto"
        })
      )

    if state == "active" do
      pursuit
    else
      pursuit
      |> Ecto.Changeset.change(state: state)
      |> Repo.update!()
    end
  end

  describe "Satisfy.execute/1" do
    test "transitions an active pursuit to satisfied and records the event" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())
      pursuit = insert_active_pursuit()
      grab_id = Ecto.UUID.generate()

      assert {:ok, %Pursuit{state: "satisfied"} = closed} =
               Satisfy.execute(%{
                 pursuit_id: pursuit.id,
                 final_target_id: grab_id,
                 final_release_title: "Sample.Movie.2010.1080p"
               })

      assert closed.id == pursuit.id

      [event] = Repo.all(Event)
      assert event.kind == "pursuit_satisfied"
      assert event.payload["final_target_id"] == grab_id
      assert event.payload["final_release_title"] == "Sample.Movie.2010.1080p"

      assert_receive %PursuitSatisfied{}
    end

    test "rejects already-terminal pursuit" do
      pursuit = insert_active_pursuit("satisfied")

      assert {:error, %Ecto.Changeset{}} =
               Satisfy.execute(%{
                 pursuit_id: pursuit.id,
                 final_target_id: Ecto.UUID.generate(),
                 final_release_title: "X"
               })
    end

    test "returns :not_found for missing pursuit" do
      assert {:error, :not_found} =
               Satisfy.execute(%{
                 pursuit_id: Ecto.UUID.generate(),
                 final_target_id: Ecto.UUID.generate(),
                 final_release_title: "X"
               })
    end
  end

  describe "Exhaust.execute/1" do
    test "transitions to exhausted and records the event" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())
      pursuit = insert_active_pursuit()

      assert {:ok, %Pursuit{state: "exhausted"}} =
               Exhaust.execute(%{
                 pursuit_id: pursuit.id,
                 reason: :max_attempts
               })

      [event] = Repo.all(Event)
      assert event.kind == "pursuit_exhausted"
      assert event.payload["reason"] == "max_attempts"

      assert_receive %PursuitExhausted{}
    end

    test "exhausting an awaiting-decision pursuit clears the awaiting flag" do
      pursuit =
        insert_active_pursuit("active")
        |> Ecto.Changeset.change(awaiting_decision_at: DateTime.utc_now(:second))
        |> Repo.update!()

      assert {:ok, %Pursuit{state: "exhausted", awaiting_decision_at: nil}} =
               Exhaust.execute(%{
                 pursuit_id: pursuit.id,
                 reason: :no_alternatives
               })
    end
  end

  describe "Cancel.execute/1" do
    test "transitions to cancelled and records the event" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())
      pursuit = insert_active_pursuit()

      assert {:ok, %Pursuit{state: "cancelled"}} =
               Cancel.execute(%{
                 pursuit_id: pursuit.id,
                 cancelled_by: :user,
                 reason: "user_request"
               })

      [event] = Repo.all(Event)
      assert event.kind == "pursuit_cancelled"
      assert event.payload["cancelled_by"] == "user"
      assert event.payload["reason"] == "user_request"

      assert_receive %PursuitCancelled{}
    end
  end
end
