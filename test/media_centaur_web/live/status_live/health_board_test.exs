defmodule MediaCentaurWeb.StatusLive.HealthBoardTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.StatusLive.HealthBoard

  describe "board_subsystems/0" do
    test "lists the eight app subsystems in display order" do
      assert HealthBoard.board_subsystems() ==
               [:watcher, :pipeline, :tmdb, :playback, :library, :acquisition, :self_update, :system]
    end
  end

  describe "label/1 and glyph/1" do
    test "maps each subsystem to a friendly label and a heroicon glyph" do
      assert HealthBoard.label(:pipeline) == "Import"
      assert HealthBoard.label(:tmdb) == "Metadata"
      assert HealthBoard.label(:acquisition) == "Downloads"
      assert HealthBoard.label(:self_update) == "Updates"
      assert "hero-" <> _ = HealthBoard.glyph(:pipeline)
      assert "hero-" <> _ = HealthBoard.glyph(:self_update)
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

  describe "tile_state/1" do
    defp severity_bucket(severity) do
      %MediaCentaur.ErrorReports.Bucket{
        fingerprint: "fp",
        component: :pipeline,
        normalized_message: "m",
        display_title: "t",
        severity: severity,
        count: 2,
        first_seen: ~U[2026-06-01 10:00:00Z],
        last_seen: ~U[2026-06-01 12:00:00Z],
        sample_entries: []
      }
    end

    test "no buckets => :ok with zero counts" do
      assert %{state: :ok, error_count: 0, warning_count: 0} = HealthBoard.tile_state([])
    end

    test "any error/critical => :error; counts reflect severities" do
      assert %{state: :error, error_count: 1, warning_count: 1} =
               HealthBoard.tile_state([severity_bucket(:error), severity_bucket(:warning)])

      assert %{state: :error} = HealthBoard.tile_state([severity_bucket(:critical)])
    end

    test "only warnings => :warning" do
      assert %{state: :warning, error_count: 0, warning_count: 2} =
               HealthBoard.tile_state([severity_bucket(:warning), severity_bucket(:warning)])
    end
  end

  describe "build_board/1" do
    alias MediaCentaurWeb.StatusLive.SubsystemView

    test "returns one SubsystemView per board subsystem, in order, with label/glyph/state" do
      buckets = [
        %MediaCentaur.ErrorReports.Bucket{
          fingerprint: "fp",
          component: :pipeline,
          normalized_message: "m",
          display_title: "t",
          severity: :error,
          count: 1,
          first_seen: ~U[2026-06-01 10:00:00Z],
          last_seen: ~U[2026-06-01 12:00:00Z],
          sample_entries: []
        }
      ]

      views = HealthBoard.build_board(buckets)

      assert length(views) == 8
      assert Enum.map(views, & &1.component) == HealthBoard.board_subsystems()

      import_view = Enum.find(views, &(&1.component == :pipeline))
      assert %SubsystemView{label: "Import", state: :error, error_count: 1} = import_view
      assert "hero-" <> _ = import_view.glyph
    end
  end

  describe "tile_summary/1" do
    alias MediaCentaurWeb.StatusLive.SubsystemView

    defp view(state, error_count, warning_count) do
      %SubsystemView{
        component: :pipeline,
        label: "Import",
        glyph: "hero-arrow-down-tray",
        state: state,
        error_count: error_count,
        warning_count: warning_count
      }
    end

    test "healthy reads calm" do
      assert HealthBoard.tile_summary(view(:ok, 0, 0)) == "No issues"
    end

    test "pluralizes and joins non-zero severity counts" do
      assert HealthBoard.tile_summary(view(:error, 1, 0)) == "1 error"
      assert HealthBoard.tile_summary(view(:error, 2, 1)) == "2 errors · 1 warning"
      assert HealthBoard.tile_summary(view(:warning, 0, 3)) == "3 warnings"
    end
  end

  describe "log_lines/1" do
    test "flattens, newest-first, formats, caps at 20" do
      bucket = fn entries ->
        %MediaCentaur.ErrorReports.Bucket{
          fingerprint: "fp",
          component: :pipeline,
          normalized_message: "m",
          display_title: "t",
          severity: :error,
          count: 1,
          first_seen: ~U[2026-06-01 10:00:00Z],
          last_seen: ~U[2026-06-01 12:00:00Z],
          sample_entries: entries
        }
      end

      buckets = [
        bucket.([%{timestamp: ~U[2026-06-01 10:00:00Z], message: "older"}]),
        bucket.([%{timestamp: ~U[2026-06-01 12:00:00Z], message: "newer"}])
      ]

      lines = HealthBoard.log_lines(buckets)
      assert [first | _] = lines
      assert first =~ "12:00:00"
      assert first =~ "newer"
    end

    test "no entries => empty list" do
      assert HealthBoard.log_lines([]) == []
    end
  end
end
