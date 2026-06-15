defmodule MediaCentaur.Acquisition.ViewModels.FormattingTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.Formatting

  describe "count/2" do
    test "no plural suffix for one" do
      assert Formatting.count(1, "episode") == "1 episode"
    end

    test "appends 's' for any other quantity" do
      assert Formatting.count(3, "episode") == "3 episodes"
      assert Formatting.count(0, "term") == "0 terms"
    end
  end
end
