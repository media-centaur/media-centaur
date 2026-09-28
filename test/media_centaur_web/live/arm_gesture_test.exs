defmodule MediaCentaurWeb.Live.ArmGestureTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Live.ArmGesture

  describe "pressed/3" do
    test "the first press arms the gesture for its target" do
      assert ArmGesture.pressed(nil, "dismiss", "group-a") == {:armed, {"dismiss", "group-a"}}
    end

    test "a second press on the same gesture and target fires and empties the slot" do
      assert ArmGesture.pressed({"dismiss", "group-a"}, "dismiss", "group-a") == {:fire, nil}
    end

    test "the same gesture on another target re-arms on the new target" do
      assert ArmGesture.pressed({"dismiss", "group-a"}, "dismiss", "group-b") ==
               {:armed, {"dismiss", "group-b"}}
    end

    test "another gesture replaces the armed one" do
      assert ArmGesture.pressed({"dismiss", "group-a"}, "delete", "group-a") ==
               {:armed, {"delete", "group-a"}}
    end

    test "a gesture without a target arms and fires on the event alone" do
      assert {:armed, slot} = ArmGesture.pressed(nil, "dismiss_all", nil)
      assert ArmGesture.pressed(slot, "dismiss_all", nil) == {:fire, nil}
    end
  end

  describe "after_event/2" do
    test "the armed gesture's own event leaves the slot for its handler to decide" do
      assert ArmGesture.after_event({"dismiss", "group-a"}, "dismiss") == {"dismiss", "group-a"}
    end

    test "any other event disarms" do
      assert ArmGesture.after_event({"dismiss", "group-a"}, "select_item") == nil
    end

    test "an empty slot stays empty" do
      assert ArmGesture.after_event(nil, "select_item") == nil
    end
  end

  describe "armed?/3 and armed_target/2" do
    test "armed? is true only for the armed gesture and target" do
      slot = {"remove_event", 7}

      assert ArmGesture.armed?(slot, "remove_event", 7)
      refute ArmGesture.armed?(slot, "remove_event", 8)
      refute ArmGesture.armed?(slot, "dismiss", 7)
      refute ArmGesture.armed?(nil, "remove_event", 7)
    end

    test "armed? without a target matches a gesture armed without one" do
      assert ArmGesture.armed?({"dismiss_all", nil}, "dismiss_all")
    end

    test "armed_target returns the target armed for the gesture, or nil" do
      assert ArmGesture.armed_target({"delete", {:file, "/a.mkv"}}, "delete") == {:file, "/a.mkv"}
      assert ArmGesture.armed_target({"delete", {:file, "/a.mkv"}}, "dismiss") == nil
      assert ArmGesture.armed_target(nil, "delete") == nil
    end

    test "armed_target over a family of events returns whichever is armed" do
      family = ~w(delete_file delete_folder)

      assert ArmGesture.armed_target({"delete_folder", {:folder, "/a"}}, family) == {:folder, "/a"}
      assert ArmGesture.armed_target({"dismiss", "group-a"}, family) == nil
      assert ArmGesture.armed_target(nil, family) == nil
    end
  end
end
