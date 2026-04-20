defmodule MediaCentarr.ControlsTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Controls

  describe "get/0" do
    test "returns all catalog defaults when no overrides" do
      resolved = Controls.get()
      assert resolved[:navigate_up].key == "ArrowUp"
      assert resolved[:navigate_up].button == 12
      assert resolved[:select].key == "Enter"
      assert resolved[:toggle_console].key == "`"
      assert resolved[:toggle_console].button == nil
    end

    test "explicit nil override is preserved (user cleared the slot)" do
      :ok = Controls.clear(:back, :keyboard)
      assert Controls.get()[:back].key == nil
    end

    test "user override beats default" do
      {:ok, _} = Controls.put(:select, :keyboard, " ")
      assert Controls.get()[:select].key == " "
    end
  end

  describe "put/3 without conflict" do
    test "sets a keyboard value" do
      assert {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      assert Controls.get()[:navigate_up].key == "w"
    end

    test "sets a gamepad button" do
      assert {:ok, _} = Controls.put(:select, :gamepad, 2)
      assert Controls.get()[:select].button == 2
    end
  end

  describe "put/3 with conflict — auto-swap" do
    test "displaced binding receives the previous resolved value" do
      # Initial: navigate_up=ArrowUp, navigate_down=ArrowDown
      # User rebinds navigate_down to ArrowUp
      assert {:ok, _} = Controls.put(:navigate_down, :keyboard, "ArrowUp")
      resolved = Controls.get()
      assert resolved[:navigate_down].key == "ArrowUp"
      # navigate_up (displaced) receives previous value of navigate_down, which was ArrowDown
      assert resolved[:navigate_up].key == "ArrowDown"
    end

    test "swap handles displaced binding when rebound value was previously overridden" do
      {:ok, _} = Controls.put(:select, :keyboard, "s")
      # select=s, back=Escape. Rebind back to s.
      {:ok, _} = Controls.put(:back, :keyboard, "s")
      resolved = Controls.get()
      assert resolved[:back].key == "s"
      # select (displaced) gets back's previous value (Escape)
      assert resolved[:select].key == "Escape"
    end

    test "keyboard and gamepad are separate namespaces — no cross-kind conflicts" do
      # button index 0 is select's default on gamepad
      # "0" is not currently used as a keyboard default
      {:ok, _} = Controls.put(:select, :keyboard, "0")
      resolved = Controls.get()
      assert resolved[:select].key == "0"
      assert resolved[:select].button == 0
    end
  end

  describe "clear/2" do
    test "sets slot to nil without swap" do
      :ok = Controls.clear(:back, :keyboard)
      resolved = Controls.get()
      assert resolved[:back].key == nil
      # No other binding was disturbed
      assert resolved[:select].key == "Enter"
    end
  end

  describe "reset_category/1" do
    test "removes only the overrides in that category" do
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      {:ok, _} = Controls.put(:play, :keyboard, "x")
      :ok = Controls.reset_category(:navigation)
      resolved = Controls.get()
      assert resolved[:navigate_up].key == "ArrowUp"
      assert resolved[:play].key == "x"
    end
  end

  describe "reset_all/0" do
    test "removes every override, keyboard and gamepad" do
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      {:ok, _} = Controls.put(:select, :gamepad, 2)
      :ok = Controls.reset_all()
      resolved = Controls.get()
      assert resolved[:navigate_up].key == "ArrowUp"
      assert resolved[:select].button == 0
    end
  end

  describe "subscribe/0 and broadcast" do
    test "put/3 broadcasts :controls_changed with resolved map" do
      :ok = Controls.subscribe()
      {:ok, _} = Controls.put(:navigate_up, :keyboard, "w")
      assert_receive {:controls_changed, map}
      assert map[:navigate_up].key == "w"
    end

    test "clear/2 broadcasts" do
      :ok = Controls.subscribe()
      :ok = Controls.clear(:back, :keyboard)
      assert_receive {:controls_changed, map}
      assert map[:back].key == nil
    end

    test "reset_all/0 broadcasts" do
      :ok = Controls.subscribe()
      :ok = Controls.reset_all()
      assert_receive {:controls_changed, _}
    end
  end

  describe "glyph_style" do
    test "defaults to xbox" do
      assert Controls.glyph_style() == "xbox"
    end

    test "round-trips playstation" do
      :ok = Controls.set_glyph_style("playstation")
      assert Controls.glyph_style() == "playstation"
    end

    test "set_glyph_style/1 broadcasts" do
      :ok = Controls.subscribe()
      :ok = Controls.set_glyph_style("playstation")
      assert_receive {:controls_changed, _}
    end
  end
end
