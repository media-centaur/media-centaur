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

  describe "group_buckets/1" do
    alias MediaCentaur.ErrorReports.Bucket

    defp bucket(component, severity) do
      %Bucket{
        fingerprint: "fp-#{component}-#{severity}",
        component: component,
        normalized_message: "msg",
        display_title: "Title",
        severity: severity,
        count: 1,
        first_seen: ~U[2026-06-01 10:00:00Z],
        last_seen: ~U[2026-06-01 12:00:00Z],
        sample_entries: []
      }
    end

    test "groups buckets by component, folding framework comps under :system" do
      buckets = [bucket(:pipeline, :error), bucket(:ecto, :warning), bucket(:system, :warning)]
      grouped = HealthBoard.group_buckets(buckets)

      assert [%Bucket{component: :pipeline}] = grouped[:pipeline]
      # :ecto folds into :system alongside the native :system bucket
      assert length(grouped[:system]) == 2
    end

    test "every board subsystem has a (possibly empty) entry" do
      grouped = HealthBoard.group_buckets([])
      for s <- HealthBoard.board_subsystems(), do: assert(grouped[s] == [])
    end
  end
end
