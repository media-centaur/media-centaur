defmodule MediaCentarr.Acquisition.Pursuits.Commands.AutoCancelTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.AutoCancel
  alias MediaCentarr.Acquisition.Pursuits.Events.AutoCancelled

  defp insert_pursuit do
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

  defp insert_active_grab(pursuit) do
    %Grab{}
    |> Ecto.Changeset.cast(
      %{
        tmdb_id: pursuit.tmdb_id,
        tmdb_type: pursuit.tmdb_type,
        title: pursuit.title,
        origin: pursuit.origin
      },
      [:tmdb_id, :tmdb_type, :title, :origin]
    )
    |> Ecto.Changeset.put_change(:pursuit_id, pursuit.id)
    |> Ecto.Changeset.put_change(:status, "searching")
    |> Repo.insert!()
  end

  describe "execute/1" do
    test "cancels the active grab linked to the pursuit and records auto_cancelled event" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.acquisition_updates())

      pursuit = insert_pursuit()
      grab = insert_active_grab(pursuit)

      assert {:ok, %Pursuit{} = same_pursuit} =
               AutoCancel.execute(%{pursuit_id: pursuit.id, reason: :zero_seeders})

      # Pursuit remains active — auto-cancel does not transition state in v1.
      # User-driven fallback or terminal close happens via other commands.
      assert same_pursuit.id == pursuit.id
      assert same_pursuit.state == "active"

      # Grab cancelled
      cancelled_grab = Repo.get!(Grab, grab.id)
      assert cancelled_grab.status == "cancelled"
      assert cancelled_grab.cancelled_reason == "zero_seeders"

      # Event recorded
      [event] = Repo.all(Event)
      assert event.kind == "auto_cancelled"
      assert event.payload == %{"reason" => "zero_seeders"}

      assert_receive %AutoCancelled{}
    end

    test "no-op when no active grab exists for the pursuit" do
      pursuit = insert_pursuit()

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
