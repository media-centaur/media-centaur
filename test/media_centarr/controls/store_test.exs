defmodule MediaCentarr.Controls.StoreTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Controls.Store

  describe "read_keyboard/0 and write_keyboard/1" do
    test "returns empty map when no entry" do
      assert Store.read_keyboard() == %{}
    end

    test "round-trips overrides" do
      :ok = Store.write_keyboard(%{"navigate_up" => "w", "select" => nil})
      assert Store.read_keyboard() == %{"navigate_up" => "w", "select" => nil}
    end

    test "write overwrites prior state" do
      :ok = Store.write_keyboard(%{"navigate_up" => "w"})
      :ok = Store.write_keyboard(%{"select" => " "})
      assert Store.read_keyboard() == %{"select" => " "}
    end
  end

  describe "read_gamepad/0 and write_gamepad/1" do
    test "returns empty map when no entry" do
      assert Store.read_gamepad() == %{}
    end

    test "round-trips integer button overrides" do
      :ok = Store.write_gamepad(%{"select" => 2, "back" => nil})
      assert Store.read_gamepad() == %{"select" => 2, "back" => nil}
    end
  end

  describe "read_glyph_style/0 and write_glyph_style/1" do
    test "defaults to xbox when no entry" do
      assert Store.read_glyph_style() == "xbox"
    end

    test "round-trips playstation" do
      :ok = Store.write_glyph_style("playstation")
      assert Store.read_glyph_style() == "playstation"
    end
  end
end
