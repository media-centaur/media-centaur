defmodule MediaCentarr.Acquisition.Pursuits.SnapshotsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Pursuit, Snapshot, Snapshots}

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

  defp insert_grab_for(pursuit) do
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
    |> Repo.insert!()
  end

  describe "build/1" do
    test "freezes pursuit, latest grab, queue state, and now into a Snapshot struct" do
      pursuit = insert_pursuit()
      grab = insert_grab_for(pursuit)

      snapshot = Snapshots.build(pursuit)

      assert %Snapshot{} = snapshot
      assert snapshot.pursuit.id == pursuit.id
      assert snapshot.latest_grab.id == grab.id
      assert is_list(snapshot.queue_state) or snapshot.queue_state == :unknown
      assert %DateTime{} = snapshot.now
    end

    test "latest_grab is nil when the pursuit has no grabs yet" do
      pursuit = insert_pursuit()
      snapshot = Snapshots.build(pursuit)
      assert snapshot.latest_grab == nil
    end

    test "now is approximately the current UTC time (second-precision)" do
      pursuit = insert_pursuit()
      before = DateTime.utc_now(:second)
      snapshot = Snapshots.build(pursuit)
      after_now = DateTime.utc_now(:second)

      assert DateTime.compare(snapshot.now, before) in [:gt, :eq]
      assert DateTime.compare(snapshot.now, after_now) in [:lt, :eq]
    end
  end
end
