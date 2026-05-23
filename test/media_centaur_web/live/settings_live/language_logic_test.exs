defmodule MediaCentaurWeb.SettingsLive.LanguageLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.SettingsLive.LanguageLogic

  describe "add/2" do
    test "resolves a display name and appends the canonical code" do
      assert LanguageLogic.add([], "French") == ["fra"]
      assert LanguageLogic.add(["eng"], "spanish") == ["eng", "spa"]
    end

    test "resolves any ISO form to the canonical code" do
      assert LanguageLogic.add([], "fr") == ["fra"]
      assert LanguageLogic.add([], "fre") == ["fra"]
    end

    test "ignores duplicates regardless of input form" do
      assert LanguageLogic.add(["fra"], "French") == ["fra"]
      assert LanguageLogic.add(["fra"], "fr") == ["fra"]
    end

    test "ignores unknown / blank / nil input" do
      assert LanguageLogic.add(["eng"], "Klingon") == ["eng"]
      assert LanguageLogic.add(["eng"], "") == ["eng"]
      assert LanguageLogic.add(["eng"], nil) == ["eng"]
    end
  end

  describe "remove/2" do
    test "removes the code" do
      assert LanguageLogic.remove(["eng", "spa", "fra"], "spa") == ["eng", "fra"]
    end

    test "matches any ISO form" do
      assert LanguageLogic.remove(["eng", "fra"], "fr") == ["eng"]
    end

    test "no-op for an absent code" do
      assert LanguageLogic.remove(["eng"], "spa") == ["eng"]
    end
  end

  describe "move_up/2 and move_down/2" do
    test "move_up swaps with the previous entry" do
      assert LanguageLogic.move_up(["eng", "spa", "fra"], "spa") == ["spa", "eng", "fra"]
    end

    test "move_up on the first entry is a no-op" do
      assert LanguageLogic.move_up(["eng", "spa"], "eng") == ["eng", "spa"]
    end

    test "move_down swaps with the next entry" do
      assert LanguageLogic.move_down(["eng", "spa", "fra"], "spa") == ["eng", "fra", "spa"]
    end

    test "move_down on the last entry is a no-op" do
      assert LanguageLogic.move_down(["eng", "spa"], "spa") == ["eng", "spa"]
    end

    test "moving an absent code is a no-op" do
      assert LanguageLogic.move_up(["eng", "spa"], "fra") == ["eng", "spa"]
      assert LanguageLogic.move_down(["eng", "spa"], "fra") == ["eng", "spa"]
    end
  end

  describe "options/0" do
    test "returns {code, name} pairs sorted by name" do
      options = LanguageLogic.options()
      assert {"eng", "English"} in options
      names = Enum.map(options, fn {_code, name} -> name end)
      assert names == Enum.sort(names)
    end
  end
end
