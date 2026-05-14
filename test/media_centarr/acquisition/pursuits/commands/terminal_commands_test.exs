defmodule MediaCentarr.Acquisition.Pursuits.Commands.TerminalCommandsTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.{Cancel, Exhaust, Satisfy}

  alias MediaCentarr.Acquisition.Pursuits.Events.{
    PursuitCancelled,
    PursuitExhausted,
    PursuitSatisfied
  }

  alias MediaCentarr.Acquisition.Target
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

    test "promotes final target to succeeded and cancels in-flight siblings" do
      # Reproduces the Project Hail Mary scenario: a satisfied pursuit
      # left in-flight `seeking` / `acquired` siblings alive, and their
      # snoozed PursueTarget workers later grabbed duplicate releases.
      {pursuit, final_target} = create_pursuit_with_target(%{status: "acquired"})

      {:ok, sibling_seeking} =
        %Target{}
        |> Ecto.Changeset.change(
          pursuit_id: pursuit.id,
          title: pursuit.title,
          origin: pursuit.origin,
          status: "seeking"
        )
        |> Repo.insert()

      {:ok, sibling_acquired} =
        %Target{}
        |> Ecto.Changeset.change(
          pursuit_id: pursuit.id,
          title: pursuit.title,
          origin: pursuit.origin,
          status: "acquired"
        )
        |> Repo.insert()

      assert {:ok, %Pursuit{state: "satisfied"}} =
               Satisfy.execute(%{
                 pursuit_id: pursuit.id,
                 final_target_id: final_target.id,
                 final_release_title: "Sample.Movie.2026.1080p"
               })

      assert Repo.get!(Target, final_target.id).status == "succeeded"

      assert Repo.get!(Target, sibling_seeking.id).status == "cancelled"
      assert Repo.get!(Target, sibling_seeking.id).cancelled_reason == "pursuit_satisfied"

      assert Repo.get!(Target, sibling_acquired.id).status == "cancelled"
      assert Repo.get!(Target, sibling_acquired.id).cancelled_reason == "pursuit_satisfied"
    end

    test "cancels in-flight targets even when final_target_id is nil" do
      # LibraryReconciler may call Satisfy without a known final target
      # (the file landed via watcher import, not via a pursuit grab).
      {pursuit, seeking} = create_pursuit_with_target(%{status: "seeking"})

      assert {:ok, %Pursuit{state: "satisfied"}} =
               Satisfy.execute(%{
                 pursuit_id: pursuit.id,
                 final_target_id: nil,
                 final_release_title: "Sample.Movie.2026.1080p"
               })

      assert Repo.get!(Target, seeking.id).status == "cancelled"
      assert Repo.get!(Target, seeking.id).cancelled_reason == "pursuit_satisfied"
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

    test "cancels in-flight targets" do
      {pursuit, seeking} = create_pursuit_with_target(%{status: "seeking"})

      assert {:ok, %Pursuit{state: "exhausted"}} =
               Exhaust.execute(%{pursuit_id: pursuit.id, reason: :max_attempts})

      assert Repo.get!(Target, seeking.id).status == "cancelled"
      assert Repo.get!(Target, seeking.id).cancelled_reason == "pursuit_exhausted"
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

    test "cancels in-flight targets" do
      {pursuit, seeking} = create_pursuit_with_target(%{status: "seeking"})

      assert {:ok, %Pursuit{state: "cancelled"}} =
               Cancel.execute(%{
                 pursuit_id: pursuit.id,
                 cancelled_by: :user,
                 reason: "user_request"
               })

      assert Repo.get!(Target, seeking.id).status == "cancelled"
      assert Repo.get!(Target, seeking.id).cancelled_reason == "pursuit_cancelled"
    end
  end
end
