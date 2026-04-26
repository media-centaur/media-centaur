defmodule MediaCentarr.Acquisition.AutoGrabPolicyTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.AutoGrabPolicy

  describe "decide/3 — capability gate" do
    test "skips with :acquisition_unavailable when prowlarr is not ready" do
      assert {:skip, :acquisition_unavailable} =
               AutoGrabPolicy.decide(false, nil, prowlarr_ready: false)
    end

    test "capability check fires before in_library check (gate is first)" do
      assert {:skip, :acquisition_unavailable} =
               AutoGrabPolicy.decide(true, nil, prowlarr_ready: false)
    end

    test "capability check fires before active-grab check" do
      assert {:skip, :acquisition_unavailable} =
               AutoGrabPolicy.decide(false, "searching", prowlarr_ready: false)
    end
  end

  describe "decide/3 — library presence" do
    test "skips with :already_in_library when the release is already on disk" do
      assert {:skip, :already_in_library} =
               AutoGrabPolicy.decide(true, nil, prowlarr_ready: true)
    end
  end

  describe "decide/3 — existing grab idempotency" do
    test "skips with :already_active when an in-flight grab exists (searching)" do
      assert {:skip, :already_active} =
               AutoGrabPolicy.decide(false, "searching", prowlarr_ready: true)
    end

    test "skips with :already_active when grab is snoozed" do
      assert {:skip, :already_active} =
               AutoGrabPolicy.decide(false, "snoozed", prowlarr_ready: true)
    end

    test "skips with :already_active when grab is grabbed" do
      assert {:skip, :already_active} =
               AutoGrabPolicy.decide(false, "grabbed", prowlarr_ready: true)
    end

    test "re-arms (returns :enqueue) when grab is cancelled" do
      assert :enqueue =
               AutoGrabPolicy.decide(false, "cancelled", prowlarr_ready: true)
    end

    test "re-arms (returns :enqueue) when grab is abandoned" do
      assert :enqueue =
               AutoGrabPolicy.decide(false, "abandoned", prowlarr_ready: true)
    end
  end

  describe "decide/3 — happy path" do
    test "enqueues when prowlarr ready, release not in library, no existing grab" do
      assert :enqueue = AutoGrabPolicy.decide(false, nil, prowlarr_ready: true)
    end
  end

  describe "decide/3 — mode = off" do
    test "skips with :mode_off when no existing grab" do
      assert {:skip, :mode_off} =
               AutoGrabPolicy.decide(false, nil, prowlarr_ready: true, mode: "off")
    end

    test "cancels with :user_disabled when an active grab exists" do
      assert {:cancel, :user_disabled} =
               AutoGrabPolicy.decide(false, "searching", prowlarr_ready: true, mode: "off")
    end

    test "cancels with :user_disabled when a snoozed grab exists" do
      assert {:cancel, :user_disabled} =
               AutoGrabPolicy.decide(false, "snoozed", prowlarr_ready: true, mode: "off")
    end

    test "is a no-op for terminal grabs (already grabbed/cancelled/abandoned)" do
      # Already grabbed: nothing to cancel, but also nothing to enqueue.
      # Returns the skip path consistent with "mode is off" rather than
      # silently re-arming a finished grab.
      assert {:skip, :mode_off} =
               AutoGrabPolicy.decide(false, "grabbed", prowlarr_ready: true, mode: "off")
    end
  end

  describe "decide/3 — mode defaults to all_releases when unspecified" do
    test "no mode opt behaves as if mode=all_releases" do
      assert :enqueue = AutoGrabPolicy.decide(false, nil, prowlarr_ready: true)
    end

    test "explicit mode=all_releases enqueues normally" do
      assert :enqueue =
               AutoGrabPolicy.decide(false, nil, prowlarr_ready: true, mode: "all_releases")
    end
  end
end
