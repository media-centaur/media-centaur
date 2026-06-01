defmodule MediaCentaurWeb.StatusLive.HealthBoardTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.StatusLive.HealthBoard

  describe "board_subsystems/0" do
    test "lists the seven app subsystems in display order" do
      assert HealthBoard.board_subsystems() ==
               [:watcher, :pipeline, :tmdb, :playback, :library, :acquisition, :system]
    end
  end

  describe "label/1 and glyph/1" do
    test "maps each subsystem to a friendly label and a heroicon glyph" do
      assert HealthBoard.label(:pipeline) == "Import"
      assert HealthBoard.label(:tmdb) == "Metadata"
      assert HealthBoard.label(:acquisition) == "Downloads"
      assert "hero-" <> _ = HealthBoard.glyph(:pipeline)
    end

    test "unknown component falls back to system" do
      assert HealthBoard.label(:phoenix) == "System"
      assert HealthBoard.glyph(:nonsense) == HealthBoard.glyph(:system)
    end
  end
end
