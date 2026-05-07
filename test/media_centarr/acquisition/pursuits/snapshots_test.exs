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

    test "thresholds is loaded onto the snapshot" do
      pursuit = insert_pursuit()
      snapshot = Snapshots.build(pursuit)
      assert %MediaCentarr.Acquisition.Pursuits.Thresholds{max_attempts: 4} = snapshot.thresholds
    end

    test "no observation timestamps → both observed? flags are false" do
      pursuit = insert_pursuit()
      snapshot = Snapshots.build(pursuit)
      assert snapshot.stall_observed? == false
      assert snapshot.zero_seeders_observed? == false
      assert snapshot.stall_window_elapsed? == false
      assert snapshot.zero_seeders_window_elapsed? == false
    end

    test "stall_first_seen_at within window → observed but not yet elapsed" do
      pursuit =
        insert_pursuit()
        |> Ecto.Changeset.change(stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -60))
        |> Repo.update!()

      snapshot = Snapshots.build(pursuit)
      assert snapshot.stall_observed? == true
      assert snapshot.stall_window_elapsed? == false
    end

    test "stall_first_seen_at older than window → observed AND elapsed" do
      pursuit =
        insert_pursuit()
        |> Ecto.Changeset.change(
          stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -25 * 3600)
        )
        |> Repo.update!()

      snapshot = Snapshots.build(pursuit)
      assert snapshot.stall_observed? == true
      assert snapshot.stall_window_elapsed? == true
    end

    test "zero_seeders_first_seen_at older than the 6h window → observed AND elapsed" do
      pursuit =
        insert_pursuit()
        |> Ecto.Changeset.change(
          zero_seeders_first_seen_at: DateTime.add(DateTime.utc_now(:second), -7 * 3600)
        )
        |> Repo.update!()

      snapshot = Snapshots.build(pursuit)
      assert snapshot.zero_seeders_observed? == true
      assert snapshot.zero_seeders_window_elapsed? == true
    end
  end
end
