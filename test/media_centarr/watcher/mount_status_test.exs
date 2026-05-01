defmodule MediaCentarr.Watcher.MountStatusTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.MountStatus

  describe "action/3 — :watching state" do
    test "same device id → keep_watching" do
      assert MountStatus.action(:watching, {8, 17}, {8, 17}) == :keep_watching
    end

    test "device disappeared → transition_unavailable" do
      assert MountStatus.action(:watching, {8, 17}, nil) == :transition_unavailable
    end

    test "minor device changed (mount over empty dir) → reinit_remount" do
      # Pre-mount /mnt/media is on rootfs (e.g. {8, 1}). After the user's
      # external drive is mounted at the same path, the kernel reports the
      # path as living on a different device (e.g. {8, 17}). inotify is
      # watching the stale rootfs inode, so no events ever fire — we must
      # detect the change here and re-init.
      assert MountStatus.action(:watching, {8, 1}, {8, 17}) == :reinit_remount
    end

    test "major device changed → reinit_remount" do
      assert MountStatus.action(:watching, {8, 1}, {9, 1}) == :reinit_remount
    end

    test "no prior device id (defensive) → keep_watching" do
      # Should not happen in production — :start_watching always captures
      # the device id on success — but if it ever does, don't churn.
      assert MountStatus.action(:watching, nil, {8, 17}) == :keep_watching
    end
  end

  describe "action/3 — :unavailable state" do
    test "device still absent → keep_unavailable" do
      assert MountStatus.action(:unavailable, nil, nil) == :keep_unavailable
    end

    test "device became present → reinit_restored" do
      assert MountStatus.action(:unavailable, nil, {8, 17}) == :reinit_restored
    end

    test "stale prior id but device became present → reinit_restored" do
      # Edge case: we transitioned to :unavailable mid-run with a stored
      # prev id. When the path becomes accessible again, treat as a
      # restoration regardless of whether the device id matches.
      assert MountStatus.action(:unavailable, {8, 17}, {8, 17}) == :reinit_restored
      assert MountStatus.action(:unavailable, {8, 17}, {8, 32}) == :reinit_restored
    end
  end

  describe "action/3 — :initializing state" do
    test "no-op regardless of ids — :start_watching handler owns this transition" do
      assert MountStatus.action(:initializing, nil, nil) == :keep_watching
      assert MountStatus.action(:initializing, nil, {8, 17}) == :keep_watching
      assert MountStatus.action(:initializing, {8, 17}, {8, 17}) == :keep_watching
      assert MountStatus.action(:initializing, {8, 17}, nil) == :keep_watching
    end
  end
end
