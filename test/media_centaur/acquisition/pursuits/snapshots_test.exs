defmodule MediaCentaur.Acquisition.Pursuits.SnapshotsTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Snapshot, Snapshots, Units}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.QueueItem

  describe "build/2" do
    test "freezes pursuit, unit, current target, queue state, and now into a Snapshot struct" do
      {pursuit, target} = create_pursuit_with_target()
      unit = Units.single!(pursuit.id)

      snapshot = Snapshots.build(pursuit, unit)

      assert %Snapshot{} = snapshot
      assert snapshot.pursuit.id == pursuit.id
      assert snapshot.unit.id == unit.id
      assert snapshot.current_target.id == target.id
      assert is_list(snapshot.queue_state) or snapshot.queue_state == :unknown
      assert %DateTime{} = snapshot.now
    end

    test "current_target is nil when the unit has no targets yet" do
      pursuit = create_pursuit()
      snapshot = Snapshots.build(pursuit, Units.single!(pursuit.id))
      assert snapshot.current_target == nil
    end

    test "now is approximately the current UTC time (second-precision)" do
      pursuit = create_pursuit()
      before = DateTime.utc_now(:second)
      snapshot = Snapshots.build(pursuit, Units.single!(pursuit.id))
      after_now = DateTime.utc_now(:second)

      assert DateTime.compare(snapshot.now, before) in [:gt, :eq]
      assert DateTime.compare(snapshot.now, after_now) in [:lt, :eq]
    end

    test "thresholds is loaded onto the snapshot" do
      pursuit = create_pursuit()
      snapshot = Snapshots.build(pursuit, Units.single!(pursuit.id))
      assert %MediaCentaur.Acquisition.Pursuits.Thresholds{max_attempts: 4} = snapshot.thresholds
    end

    test "no observation timestamps → both observed? flags are false" do
      pursuit = create_pursuit()
      snapshot = Snapshots.build(pursuit, Units.single!(pursuit.id))
      assert snapshot.stall_observed? == false
      assert snapshot.zero_seeders_observed? == false
      assert snapshot.stall_window_elapsed? == false
      assert snapshot.zero_seeders_window_elapsed? == false
    end

    test "stall_first_seen_at within window → observed but not yet elapsed" do
      pursuit =
        create_pursuit(%{stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -60)})

      snapshot = Snapshots.build(pursuit, Units.single!(pursuit.id))
      assert snapshot.stall_observed? == true
      assert snapshot.stall_window_elapsed? == false
    end

    test "stall_first_seen_at older than window → observed AND elapsed" do
      pursuit =
        create_pursuit(%{
          stall_first_seen_at: DateTime.add(DateTime.utc_now(:second), -25 * 3600)
        })

      snapshot = Snapshots.build(pursuit, Units.single!(pursuit.id))
      assert snapshot.stall_observed? == true
      assert snapshot.stall_window_elapsed? == true
    end

    test "zero_seeders_first_seen_at older than the 6h window → observed AND elapsed" do
      pursuit =
        create_pursuit(%{
          zero_seeders_first_seen_at: DateTime.add(DateTime.utc_now(:second), -7 * 3600)
        })

      snapshot = Snapshots.build(pursuit, Units.single!(pursuit.id))
      assert snapshot.zero_seeders_observed? == true
      assert snapshot.zero_seeders_window_elapsed? == true
    end
  end

  describe "build/4 — download_failure_message" do
    # The client's terminal-failure detail (SABnzbd's `fail_message`) is
    # the failure signal itself — presence means the client declared the
    # download unrecoverable. It rides the snapshot so the auto-cancel
    # event can record *why*, not just that it happened.

    defp release_target(release_title) do
      struct(Target, %{release_title: release_title, torrent_hash: nil})
    end

    defp failed_item(title, failure_message) do
      %QueueItem{id: "nzo_1", title: title, state: :error, failure_message: failure_message}
    end

    test "carries the matched item's failure message" do
      pursuit = create_pursuit()
      unit = Units.single!(pursuit.id)
      queue = [failed_item("Sample.Show.S01E01.1080p", "Repair failed, not enough repair blocks")]

      snapshot = Snapshots.build(pursuit, unit, queue, release_target("Sample.Show.S01E01.1080p"))

      assert snapshot.download_failure_message == "Repair failed, not enough repair blocks"
    end

    test "nil when the matched item errored without a failure detail (ambiguous torrent error)" do
      pursuit = create_pursuit()
      unit = Units.single!(pursuit.id)
      queue = [failed_item("Sample.Show.S01E01.1080p", nil)]

      snapshot = Snapshots.build(pursuit, unit, queue, release_target("Sample.Show.S01E01.1080p"))

      assert snapshot.download_failure_message == nil
    end

    test "nil when the queue state is unknown or there is no current target" do
      pursuit = create_pursuit()
      unit = Units.single!(pursuit.id)

      assert Snapshots.build(pursuit, unit, :unknown, release_target("X")).download_failure_message ==
               nil

      assert Snapshots.build(pursuit, unit, [], nil).download_failure_message == nil
    end
  end
end
