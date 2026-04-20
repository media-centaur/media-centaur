defmodule MediaCentarrWeb.SettingsLive.ControlsLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.SettingsLive.ControlsLogic

  describe "group_for_view/1" do
    test "returns ordered list of {category, [binding_view]} tuples" do
      resolved = %{
        navigate_up: %{key: "w", button: 12},
        navigate_down: %{key: "s", button: 13},
        navigate_left: %{key: "a", button: 14},
        navigate_right: %{key: "d", button: 15},
        select: %{key: "Enter", button: 0},
        back: %{key: nil, button: 1},
        clear: %{key: "Backspace", button: 3},
        zone_next: %{key: "]", button: 5},
        zone_prev: %{key: "[", button: 4},
        play: %{key: "p", button: 9},
        toggle_console: %{key: "`", button: nil}
      }

      [{:navigation, nav}, {:zones, zones}, {:playback, play}, {:system, sys}] =
        ControlsLogic.group_for_view(resolved)

      assert length(nav) == 7
      assert length(zones) == 2
      assert length(play) == 1
      assert length(sys) == 1

      [first | _] = nav
      assert first.id == :navigate_up
      assert first.key == "w"
      assert first.button == 12
      assert first.name == "Move up"
    end
  end

  describe "display_key/1" do
    test "pretty-prints special keys" do
      assert ControlsLogic.display_key("ArrowUp") == "↑"
      assert ControlsLogic.display_key("ArrowDown") == "↓"
      assert ControlsLogic.display_key("ArrowLeft") == "←"
      assert ControlsLogic.display_key("ArrowRight") == "→"
      assert ControlsLogic.display_key("Enter") == "Enter"
      assert ControlsLogic.display_key("Escape") == "Esc"
      assert ControlsLogic.display_key("Backspace") == "Backspace"
      assert ControlsLogic.display_key(" ") == "Space"
    end

    test "uppercases single letters" do
      assert ControlsLogic.display_key("p") == "P"
    end

    test "returns key as-is for symbols" do
      assert ControlsLogic.display_key("[") == "["
      assert ControlsLogic.display_key("]") == "]"
      assert ControlsLogic.display_key("`") == "`"
    end

    test "returns nil when key is nil" do
      assert ControlsLogic.display_key(nil) == nil
    end
  end

  describe "display_button/2" do
    test "xbox labels face buttons" do
      assert ControlsLogic.display_button(0, "xbox") == "A"
      assert ControlsLogic.display_button(1, "xbox") == "B"
      assert ControlsLogic.display_button(2, "xbox") == "X"
      assert ControlsLogic.display_button(3, "xbox") == "Y"
    end

    test "playstation labels face buttons" do
      assert ControlsLogic.display_button(0, "playstation") == "✕"
      assert ControlsLogic.display_button(1, "playstation") == "○"
      assert ControlsLogic.display_button(2, "playstation") == "□"
      assert ControlsLogic.display_button(3, "playstation") == "△"
    end

    test "xbox labels shoulders" do
      assert ControlsLogic.display_button(4, "xbox") == "LB"
      assert ControlsLogic.display_button(5, "xbox") == "RB"
    end

    test "playstation labels shoulders" do
      assert ControlsLogic.display_button(4, "playstation") == "L1"
      assert ControlsLogic.display_button(5, "playstation") == "R1"
    end

    test "labels dpad consistently across styles" do
      assert ControlsLogic.display_button(12, "xbox") == "D-Pad ↑"
      assert ControlsLogic.display_button(13, "xbox") == "D-Pad ↓"
      assert ControlsLogic.display_button(14, "xbox") == "D-Pad ←"
      assert ControlsLogic.display_button(15, "xbox") == "D-Pad →"
    end

    test "labels options button per platform" do
      assert ControlsLogic.display_button(9, "xbox") == "Menu"
      assert ControlsLogic.display_button(9, "playstation") == "Options"
    end

    test "returns nil for nil" do
      assert ControlsLogic.display_button(nil, "xbox") == nil
    end

    test "returns fallback for unknown indices" do
      assert ControlsLogic.display_button(99, "xbox") == "Btn 99"
    end
  end

  describe "pending_swap/3" do
    test "returns the id that would be displaced on a conflicting put" do
      resolved = %{
        navigate_up: %{key: "ArrowUp", button: 12},
        navigate_down: %{key: "ArrowDown", button: 13}
      }

      assert ControlsLogic.pending_swap(resolved, :navigate_up, "ArrowDown", :keyboard) ==
               :navigate_down
    end

    test "returns nil when no conflict" do
      resolved = %{navigate_up: %{key: "ArrowUp", button: 12}}
      assert ControlsLogic.pending_swap(resolved, :navigate_up, "w", :keyboard) == nil
    end

    test "ignores self" do
      resolved = %{select: %{key: "Enter", button: 0}}
      assert ControlsLogic.pending_swap(resolved, :select, "Enter", :keyboard) == nil
    end
  end
end
