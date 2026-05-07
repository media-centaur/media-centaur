defmodule MediaCentarr.Acquisition.PursuitsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits
  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}

  defp insert_pursuit(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          tmdb_id: "12345",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto"
        },
        overrides
      )

    {:ok, pursuit} = Repo.insert(Pursuit.create_changeset(attrs))
    pursuit
  end

  defp set_state(pursuit, new_state) do
    pursuit
    |> Ecto.Changeset.change(state: new_state)
    |> Repo.update!()
  end

  defp insert_event(pursuit, kind, occurred_at) do
    {:ok, event} =
      Repo.insert(
        Event.create_changeset(%{
          pursuit_id: pursuit.id,
          denormalized_pursuit_title: pursuit.title,
          kind: kind,
          payload: %{},
          occurred_at: occurred_at
        })
      )

    event
  end

  defp insert_grab_for(pursuit, attrs \\ %{}) do
    base = %{
      tmdb_id: pursuit.tmdb_id,
      tmdb_type: pursuit.tmdb_type,
      title: pursuit.title,
      origin: pursuit.origin
    }

    %Grab{}
    |> Ecto.Changeset.cast(Map.merge(base, attrs), [:tmdb_id, :tmdb_type, :title, :origin])
    |> Ecto.Changeset.put_change(:pursuit_id, pursuit.id)
    |> Repo.insert!()
  end

  describe "get/1" do
    test "returns the pursuit by id" do
      pursuit = insert_pursuit()
      assert {:ok, fetched} = Pursuits.get(pursuit.id)
      assert fetched.id == pursuit.id
    end

    test "returns :not_found when missing" do
      assert {:error, :not_found} = Pursuits.get(Ecto.UUID.generate())
    end
  end

  describe "list_active/0" do
    test "returns only in-flight pursuits, newest first" do
      _terminal = set_state(insert_pursuit(), "satisfied")
      active_old = insert_pursuit(%{tmdb_id: "111", title: "Old"})
      :timer.sleep(1100)
      active_new = insert_pursuit(%{tmdb_id: "222", title: "New"})

      ids = Enum.map(Pursuits.list_active(), & &1.id)

      assert active_new.id in ids
      assert active_old.id in ids
      refute Enum.any?(ids, fn id -> id == _terminal.id end)
    end

    test "needs_decision pursuits also count as active" do
      pursuit = set_state(insert_pursuit(), "needs_decision")
      ids = Enum.map(Pursuits.list_active(), & &1.id)
      assert pursuit.id in ids
    end

    test "excludes satisfied, exhausted, and cancelled" do
      satisfied = set_state(insert_pursuit(%{tmdb_id: "1"}), "satisfied")
      exhausted = set_state(insert_pursuit(%{tmdb_id: "2"}), "exhausted")
      cancelled = set_state(insert_pursuit(%{tmdb_id: "3"}), "cancelled")

      ids = Enum.map(Pursuits.list_active(), & &1.id)

      refute satisfied.id in ids
      refute exhausted.id in ids
      refute cancelled.id in ids
    end
  end

  describe "events_for/1" do
    test "returns events for a pursuit, newest first" do
      pursuit = insert_pursuit()
      old = insert_event(pursuit, "pursuit_started", DateTime.add(DateTime.utc_now(:second), -60))
      new = insert_event(pursuit, "release_picked", DateTime.utc_now(:second))

      [first, second] = Pursuits.events_for(pursuit.id)
      assert first.id == new.id
      assert second.id == old.id
    end

    test "returns empty list for unknown pursuit_id" do
      assert Pursuits.events_for(Ecto.UUID.generate()) == []
    end
  end

  describe "latest_grab/1" do
    test "returns the most recently inserted grab linked to the pursuit" do
      pursuit = insert_pursuit()
      _old = insert_grab_for(pursuit)
      :timer.sleep(1100)
      newer = insert_grab_for(pursuit, %{title: "Newer attempt"})

      assert {:ok, found} = Pursuits.latest_grab(pursuit.id)
      assert found.id == newer.id
    end

    test "returns :not_found when no grabs exist" do
      pursuit = insert_pursuit()
      assert {:error, :not_found} = Pursuits.latest_grab(pursuit.id)
    end
  end
end
