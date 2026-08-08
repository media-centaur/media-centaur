defmodule MediaCentaurWeb.Components.DetailPanelTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.Components.DetailPanel

  describe "scrollable_content?/2" do
    # Entities arrive as the loose modal-entry map shape (`entity: :map`
    # on the component) — minimal maps mirror that contract.

    test "true for TV series and movie series regardless of view" do
      assert DetailPanel.scrollable_content?(%{type: :tv_series}, :main)
      assert DetailPanel.scrollable_content?(%{type: :movie_series}, :main)
    end

    test "false for a bare movie on the main view" do
      refute DetailPanel.scrollable_content?(%{type: :movie, extras: []}, :main)
    end

    test "true for any entity on the Manage or Cast sub-views" do
      assert DetailPanel.scrollable_content?(%{type: :movie, extras: []}, :info)
      assert DetailPanel.scrollable_content?(%{type: :movie, extras: []}, :cast)
    end

    test "true for a movie carrying entity-level extras" do
      extra = build_extra(%{owner_type: :movie})

      assert DetailPanel.scrollable_content?(%{type: :movie, extras: [extra]}, :main)
    end

    test "season-owned extras alone do not make a movie scrollable" do
      extra = build_extra(%{owner_type: :season})

      refute DetailPanel.scrollable_content?(%{type: :movie, extras: [extra]}, :main)
    end
  end

  describe "blur_spoilers?/2" do
    test "blurs a fully-unwatched episode in spoiler-free mode" do
      assert DetailPanel.blur_spoilers?(true, :unwatched)
    end

    test "never blurs a watched or in-progress episode, even in spoiler-free mode" do
      refute DetailPanel.blur_spoilers?(true, :watched)
      refute DetailPanel.blur_spoilers?(true, :current)
    end

    test "never blurs when spoiler-free mode is off" do
      refute DetailPanel.blur_spoilers?(false, :unwatched)
    end
  end

  # `delete_gesture_state/3` and `delete_in_flight?/1` moved to
  # `MediaCentaurWeb.LiveHelpers` (see live_helpers_test.exs) — shared with
  # Review's delete gesture, no longer DetailPanel-specific.

  # `auto_expand_season/2` was removed by the 2026-08-04 orientation
  # design — seasons always open collapsed; the hero orientation block
  # answers "where am I".

  # --- overall_progress_percent/2 ---

  describe "overall_progress_percent/2" do
    test "returns 0 for nil progress" do
      assert DetailPanel.overall_progress_percent(nil, build_entity()) == 0
    end

    test "computes episode-based percentage for tv_series" do
      progress = %{episodes_completed: 3, episodes_total: 10}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.overall_progress_percent(progress, entity) == 30
    end

    test "computes episode-based percentage for movie_series" do
      progress = %{episodes_completed: 2, episodes_total: 3}
      entity = build_entity(%{type: :movie_series})

      assert DetailPanel.overall_progress_percent(progress, entity) == 67
    end

    test "returns 0 when episodes_total is 0 for series" do
      progress = %{episodes_completed: 0, episodes_total: 0}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.overall_progress_percent(progress, entity) == 0
    end

    test "computes position-based percentage for standalone movie" do
      progress = %{
        episode_position_seconds: 1800.0,
        episode_duration_seconds: 3600.0,
        episodes_completed: 0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.overall_progress_percent(progress, entity) == 50
    end

    test "returns 100 when completed but no duration for movie" do
      progress = %{
        episode_position_seconds: 0.0,
        episode_duration_seconds: 0.0,
        episodes_completed: 1
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.overall_progress_percent(progress, entity) == 100
    end

    test "caps at 100" do
      progress = %{episodes_completed: 11, episodes_total: 10}
      entity = build_entity(%{type: :tv_series})

      assert DetailPanel.overall_progress_percent(progress, entity) == 100
    end
  end

  # --- progress_remaining_text/2 ---

  describe "progress_remaining_text/2" do
    test "returns nil for nil progress" do
      assert DetailPanel.progress_remaining_text(nil, build_entity()) == nil
    end

    # No tv_series cases: TV remaining-text moved to the hero subline
    # (`MediaCentaurWeb.ViewModel.Orientation`) in the 2026-08-04
    # orientation design; the PlayCard row no longer renders for TV.

    test "returns movie count for movie_series" do
      progress = %{episodes_total: 3, episodes_completed: 1}
      entity = build_entity(%{type: :movie_series})

      assert DetailPanel.progress_remaining_text(progress, entity) == "2 movies left"
    end

    test "returns Watched for completed standalone movie" do
      progress = %{
        episodes_completed: 1,
        episode_duration_seconds: 0.0,
        episode_position_seconds: 0.0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.progress_remaining_text(progress, entity) == "Watched"
    end

    test "returns time remaining for in-progress standalone movie" do
      progress = %{
        episodes_completed: 0,
        episode_duration_seconds: 7200.0,
        episode_position_seconds: 3600.0
      }

      entity = build_entity(%{type: :movie})

      assert DetailPanel.progress_remaining_text(progress, entity) == "1h remaining"
    end
  end

  # --- episode_state/1 ---

  describe "episode_state/1" do
    test "returns :unwatched for nil" do
      assert DetailPanel.episode_state(nil) == :unwatched
    end

    test "returns :watched when completed" do
      progress = %{completed: true, position_seconds: 2700.0}
      assert DetailPanel.episode_state(progress) == :watched
    end

    test "returns :current when has position" do
      progress = %{completed: false, position_seconds: 100.0}
      assert DetailPanel.episode_state(progress) == :current
    end

    test "returns :unwatched when no position and not completed" do
      progress = %{completed: false, position_seconds: 0.0}
      assert DetailPanel.episode_state(progress) == :unwatched
    end
  end

  # --- episode_row_class/2 ---

  describe "episode_row_class/2" do
    test "returns primary highlight when resume target" do
      assert DetailPanel.episode_row_class(:watched, true) == "bg-primary/10"
    end

    test "returns opacity for watched" do
      assert DetailPanel.episode_row_class(:watched, false) == "opacity-60"
    end

    test "returns info bg for current" do
      assert DetailPanel.episode_row_class(:current, false) == "bg-info/5"
    end

    test "returns empty for unwatched" do
      assert DetailPanel.episode_row_class(:unwatched, false) == ""
    end
  end

  # --- progress_percent/1 ---

  describe "progress_percent/1" do
    test "computes percentage from position and duration" do
      assert DetailPanel.progress_percent(%{position_seconds: 900, duration_seconds: 3600}) == 25
    end

    test "caps at 100" do
      assert DetailPanel.progress_percent(%{position_seconds: 4000, duration_seconds: 3600}) ==
               100
    end

    test "returns 0 for nil" do
      assert DetailPanel.progress_percent(nil) == 0
    end

    test "returns 0 when duration is 0" do
      assert DetailPanel.progress_percent(%{position_seconds: 100, duration_seconds: 0}) == 0
    end
  end

  # --- format_file_size/1 ---

  describe "file_tech_line/1" do
    defp probed_media_info(overrides) do
      Map.merge(
        %{
          container_title: nil,
          duration_seconds: 6073,
          video_codec: "HEVC",
          width: 3840,
          height: 2160,
          audio_summary: "TrueHD 7.1"
        },
        overrides
      )
    end

    test "joins duration, codec, resolution, and audio with dots" do
      assert DetailPanel.file_tech_line(probed_media_info(%{})) ==
               "1h 41m · HEVC · 3840×2160 · TrueHD 7.1"
    end

    test "durations under an hour omit the hour segment (UIDR-004)" do
      assert DetailPanel.file_tech_line(probed_media_info(%{duration_seconds: 2712})) =~ "45m ·"
      refute DetailPanel.file_tech_line(probed_media_info(%{duration_seconds: 2712})) =~ "0h"
    end

    test "missing facts drop out instead of leaving separators" do
      line =
        DetailPanel.file_tech_line(
          probed_media_info(%{video_codec: nil, width: nil, height: nil, audio_summary: nil})
        )

      assert line == "1h 41m"
    end

    test "nothing probed is the empty string" do
      empty =
        probed_media_info(%{
          duration_seconds: nil,
          video_codec: nil,
          width: nil,
          height: nil,
          audio_summary: nil
        })

      assert DetailPanel.file_tech_line(empty) == ""
    end
  end

  describe "format_file_size/1" do
    test "formats gigabytes" do
      assert DetailPanel.format_file_size(2_147_483_648) == "2.0 GB"
    end

    test "formats megabytes" do
      assert DetailPanel.format_file_size(10_485_760) == "10.0 MB"
    end

    test "formats kilobytes" do
      assert DetailPanel.format_file_size(2048) == "2.0 KB"
    end

    test "formats bytes" do
      assert DetailPanel.format_file_size(512) == "512 B"
    end
  end

  # --- file_summary/2 ---

  describe "file_summary/2" do
    test "formats singular file count" do
      assert DetailPanel.file_summary(1, 1_073_741_824) == "1 file, 1.0 GB"
    end

    test "formats plural file count" do
      assert DetailPanel.file_summary(3, 3_145_728) == "3 files, 3.0 MB"
    end
  end

  # --- build_file_groups/2 ---

  describe "build_file_groups/2" do
    test "groups files by directory" do
      files = [
        %{file: %{file_path: "/media/movies/Sample Movie/movie.mkv"}, size: 4_000_000_000},
        %{file: %{file_path: "/media/movies/Sample Movie/extras.mkv"}, size: 1_000_000_000}
      ]

      result = DetailPanel.build_file_groups(files, MapSet.new())

      assert [%{dir: "/media/movies/Sample Movie", name: "Sample Movie", files: files_list}] = result
      assert length(files_list) == 2
    end

    test "sorts groups by directory path" do
      files = [
        %{file: %{file_path: "/z-dir/movie.mkv"}, size: 100},
        %{file: %{file_path: "/a-dir/movie.mkv"}, size: 200}
      ]

      result = DetailPanel.build_file_groups(files, MapSet.new())

      assert [%{dir: "/a-dir"}, %{dir: "/z-dir"}] = result
    end

    test "flags media directories" do
      files = [
        %{file: %{file_path: "/watch/movie.mkv"}, size: 100},
        %{file: %{file_path: "/other/movie.mkv"}, size: 200}
      ]

      media_dirs = MapSet.new(["/watch"])
      result = DetailPanel.build_file_groups(files, media_dirs)

      watch_group = Enum.find(result, &(&1.dir == "/watch"))
      other_group = Enum.find(result, &(&1.dir == "/other"))

      assert watch_group.is_media_dir == true
      assert other_group.is_media_dir == false
    end

    test "returns empty list for empty files" do
      assert DetailPanel.build_file_groups([], MapSet.new()) == []
    end
  end

  # --- build_delete_all_payload/2 ---

  describe "build_delete_all_payload/2" do
    test "builds grouped payload with totals" do
      files = [
        %{file: %{file_path: "/media/SampleShow/ep1.mkv"}, size: 4_000_000_000},
        %{file: %{file_path: "/media/SampleShow/ep2.mkv"}, size: 3_000_000_000},
        %{file: %{file_path: "/other/movie.mkv"}, size: 2_000_000_000}
      ]

      result = DetailPanel.build_delete_all_payload(files, MapSet.new())

      assert result.file_count == 3
      assert result.total_size == 9_000_000_000

      assert length(result.file_groups) == 2

      shoresy_group = Enum.find(result.file_groups, &(&1.name == "SampleShow"))
      assert length(shoresy_group.files) == 2
      assert Enum.all?(shoresy_group.files, &Map.has_key?(&1, :path))
      assert Enum.all?(shoresy_group.files, &Map.has_key?(&1, :name))
      assert Enum.all?(shoresy_group.files, &Map.has_key?(&1, :size))
    end

    test "flags media directories in payload" do
      files = [
        %{file: %{file_path: "/watch/movie.mkv"}, size: 100}
      ]

      result = DetailPanel.build_delete_all_payload(files, MapSet.new(["/watch"]))

      assert [%{is_media_dir: true}] = result.file_groups
    end

    test "handles nil sizes gracefully" do
      files = [
        %{file: %{file_path: "/dir/movie.mkv"}, size: nil},
        %{file: %{file_path: "/dir/other.mkv"}, size: 1000}
      ]

      result = DetailPanel.build_delete_all_payload(files, MapSet.new())

      assert result.total_size == 1000
      assert result.file_count == 2
    end
  end

  # `build_episode_list/2` and `count_watched_episodes/2` were
  # extracted into `MediaCentaurWeb.ViewModel.SeriesDetail` (see
  # `test/media_centaur_web/view_model/series_detail_test.exs`) when
  # the TV-series path migrated to typed view-models. Behavioural
  # coverage lives there now: gap-filling, watched_count, total_count.

  describe "upcoming_pill_copy/2" do
    test "future date within 14 days reads 'in Xd'" do
      today = ~D[2026-05-08]
      assert DetailPanel.upcoming_pill_copy(%{air_date: ~D[2026-05-15]}, today) == "in 7d"
      assert DetailPanel.upcoming_pill_copy(%{air_date: ~D[2026-05-09]}, today) == "in 1d"
    end

    test "today reads 'today'" do
      today = ~D[2026-05-08]
      assert DetailPanel.upcoming_pill_copy(%{air_date: ~D[2026-05-08]}, today) == "today"
    end

    test "past date within 14 days reads 'aired Xd ago'" do
      today = ~D[2026-05-08]
      assert DetailPanel.upcoming_pill_copy(%{air_date: ~D[2026-05-05]}, today) == "aired 3d ago"
      assert DetailPanel.upcoming_pill_copy(%{air_date: ~D[2026-05-07]}, today) == "aired 1d ago"
    end

    test "further-out future date renders the formatted month/day" do
      today = ~D[2026-05-08]
      assert DetailPanel.upcoming_pill_copy(%{air_date: ~D[2026-08-15]}, today) == "Aug 15"
    end

    test "further-out past date renders the formatted month/day" do
      today = ~D[2026-05-08]
      assert DetailPanel.upcoming_pill_copy(%{air_date: ~D[2026-01-04]}, today) == "Jan 4"
    end

    test "nil air_date renders 'TBA'" do
      assert DetailPanel.upcoming_pill_copy(%{air_date: nil}, ~D[2026-05-08]) == "TBA"
    end
  end
end
