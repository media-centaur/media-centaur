defmodule MediaCentaurWeb.StatusLive.HealthBoardTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.StatusLive.HealthBoard

  describe "board_subsystems/0" do
    test "lists the ten app subsystems in display order" do
      assert HealthBoard.board_subsystems() ==
               [
                 :watcher,
                 :pipeline,
                 :tmdb,
                 :http,
                 :playback,
                 :library,
                 :acquisition,
                 :social,
                 :self_update,
                 :system
               ]
    end
  end

  describe "label/1 and glyph/1" do
    test "maps each subsystem to a friendly label and a heroicon glyph" do
      assert HealthBoard.label(:pipeline) == "Media import"
      assert HealthBoard.label(:tmdb) == "Metadata"
      assert HealthBoard.label(:acquisition) == "Downloads"
      assert HealthBoard.label(:social) == "Social"
      assert HealthBoard.label(:self_update) == "Updates"
      assert "hero-" <> _ = HealthBoard.glyph(:pipeline)
      assert "hero-" <> _ = HealthBoard.glyph(:self_update)
    end

    test "unknown component falls back to system" do
      assert HealthBoard.label(:phoenix) == "System"
      assert HealthBoard.glyph(:nonsense) == HealthBoard.glyph(:system)
    end
  end

  describe "description/1" do
    test "every board subsystem has a non-empty plain-language description" do
      for component <- HealthBoard.board_subsystems() do
        description = HealthBoard.description(component)
        assert is_binary(description)
        assert String.length(description) > 0
      end
    end

    test "unknown component falls back to the system description" do
      assert HealthBoard.description(:phoenix) == HealthBoard.description(:system)
      assert HealthBoard.description(:nonsense) == HealthBoard.description(:system)
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

    test "aliases the :nostr log component onto the social tile" do
      buckets = [
        bucket(:nostr, :warning),
        bucket(:social, :error),
        bucket(:phoenix, :warning)
      ]

      grouped = HealthBoard.group_buckets(buckets)

      assert length(grouped[:social]) == 2
      # an unrelated, unknown component still folds to :system
      assert length(grouped[:system]) == 1
    end
  end

  describe "tile_state/1" do
    defp severity_bucket(severity, component \\ :pipeline) do
      %MediaCentaur.ErrorReports.Bucket{
        fingerprint: "fp",
        component: component,
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

  describe "build_board/2" do
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

      views = HealthBoard.build_board(buckets, MapSet.new())

      assert length(views) == 10
      assert Enum.map(views, & &1.component) == HealthBoard.board_subsystems()

      import_view = Enum.find(views, &(&1.component == :pipeline))
      assert %SubsystemView{label: "Media import", state: :error, error_count: 1} = import_view
      assert "hero-" <> _ = import_view.glyph
    end

    test "an otherwise-healthy subsystem whose prerequisite is unconfigured reads dormant" do
      views = HealthBoard.build_board([], MapSet.new([:tmdb, :acquisition]))

      assert %SubsystemView{state: :dormant} = Enum.find(views, &(&1.component == :tmdb))
      assert %SubsystemView{state: :dormant} = Enum.find(views, &(&1.component == :acquisition))
      assert %SubsystemView{state: :ok} = Enum.find(views, &(&1.component == :library))
    end

    test "a real error outranks dormancy — an unconfigured subsystem that failed still reads error" do
      buckets = [severity_bucket(:error, :tmdb)]

      views = HealthBoard.build_board(buckets, MapSet.new([:tmdb]))

      assert %SubsystemView{state: :error, error_count: 1} =
               Enum.find(views, &(&1.component == :tmdb))
    end
  end

  describe "dormant_components/1" do
    test "media directories gate the two subsystems that read them" do
      dormant =
        HealthBoard.dormant_components(%{media_dirs: false, tmdb: true, acquisition: true, social: true})

      assert :watcher in dormant
      assert :pipeline in dormant
      refute :tmdb in dormant
    end

    test "each remaining prerequisite gates its own subsystem" do
      dormant =
        HealthBoard.dormant_components(%{
          media_dirs: true,
          tmdb: false,
          acquisition: false,
          social: false
        })

      assert Enum.sort(dormant) == [:acquisition, :social, :tmdb]
    end

    test "a fully configured install has no dormant subsystems" do
      assert Enum.empty?(
               HealthBoard.dormant_components(%{
                 media_dirs: true,
                 tmdb: true,
                 acquisition: true,
                 social: true
               })
             )
    end
  end

  describe "dormant_remedy/1" do
    test "every subsystem that can go dormant names the one action that starts it" do
      for component <- [:watcher, :pipeline, :tmdb, :acquisition, :social] do
        remedy = HealthBoard.dormant_remedy(component)
        assert is_binary(remedy) and remedy != ""
        assert remedy =~ "Settings"
      end
    end
  end

  describe "tile_summary/1" do
    alias MediaCentaurWeb.StatusLive.SubsystemView

    defp view(state, error_count, warning_count) do
      %SubsystemView{
        component: :pipeline,
        label: "Media import",
        glyph: "hero-arrow-down-tray",
        state: state,
        error_count: error_count,
        warning_count: warning_count
      }
    end

    test "healthy reads calm" do
      assert HealthBoard.tile_summary(view(:ok, 0, 0)) == "No issues"
    end

    test "dormant names the state rather than claiming health" do
      assert HealthBoard.tile_summary(view(:dormant, 0, 0)) == "Not configured"
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
