defmodule MediaCentarr.Acquisition.Pursuits.SnapshotsTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Pursuits.{Snapshot, Snapshots}

  describe "build/1" do
    test "freezes pursuit, current target, queue state, and now into a Snapshot struct" do
      {pursuit, target} = create_pursuit_with_target()

      snapshot = Snapshots.build(pursuit)

      assert %Snapshot{} = snapshot
      assert snapshot.pursuit.id == pursuit.id
      assert snapshot.current_target.id == target.id
      assert is_list(snapshot.queue_state) or snapshot.queue_state == :unknown
      assert %DateTime{} = snapshot.now
    end

    test "current_target is nil when the pursuit has no targets yet" do
      pursuit = create_pursuit()
      snapshot = Snapshots.build(pursuit)
      assert snapshot.current_target == nil
    end

    test "now is approximately the current UTC time (second-precision)" do
      pursuit = create_pursuit()
      before = DateTime.utc_now(:second)
      snapshot = Snapshots.build(pursuit)
      after_now = DateTime.utc_now(:second)

      assert DateTime.compare(snapshot.now, before) in [:gt, :eq]
      assert DateTime.compare(snapshot.now, after_now) in [:lt, :eq]
    end

    test "thresholds is loaded onto the snapshot" do
      pursuit = create_pursuit()
      snapshot = Snapshots.build(pursuit)
      assert %MediaCentarr.Acquisition.Pursuits.Thresholds{max_attempts: 4} = snapshot.thresholds
    end

    test "no observation timestamps → both observed? flags are false" do
      pursuit = create_pursuit()
      snapshot = Snapshots.build(pursuit)
      assert snapshot.stall_observed? == false
      assert snapshot.zero_seeders_observed? == false
      assert snapshot.stall_window_elapsed? == false
      assert snapshot.zero_seeders_window_elapsed? == false
    end

    test "stall_first_seen_at within window → observed but not yet elapsed" do
      pursuit =
        create_pursuit()
        |> Ecto.Changeset.change(stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -60))
        |> Repo.update!()

      snapshot = Snapshots.build(pursuit)
      assert snapshot.stall_observed? == true
      assert snapshot.stall_window_elapsed? == false
    end

    test "stall_first_seen_at older than window → observed AND elapsed" do
      pursuit =
        create_pursuit()
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
        create_pursuit()
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
