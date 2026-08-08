defmodule MediaCentaurWeb.Components.Detail.ManagePanelTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Detail.ManagePanel

  # Helper tests moved here from `DetailPanelTest` when the Manage sheet
  # was extracted into its own component (2026-08-08 overhaul).

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
      assert ManagePanel.file_tech_line(probed_media_info(%{})) ==
               "1h 41m · HEVC · 3840×2160 · TrueHD 7.1"
    end

    test "durations under an hour omit the hour segment (UIDR-004)" do
      assert ManagePanel.file_tech_line(probed_media_info(%{duration_seconds: 2712})) =~ "45m ·"
      refute ManagePanel.file_tech_line(probed_media_info(%{duration_seconds: 2712})) =~ "0h"
    end

    test "missing facts drop out instead of leaving separators" do
      line =
        ManagePanel.file_tech_line(
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

      assert ManagePanel.file_tech_line(empty) == ""
    end
  end

  describe "format_file_size/1" do
    test "formats gigabytes" do
      assert ManagePanel.format_file_size(2_147_483_648) == "2.0 GB"
    end

    test "formats megabytes" do
      assert ManagePanel.format_file_size(10_485_760) == "10.0 MB"
    end

    test "formats kilobytes" do
      assert ManagePanel.format_file_size(2048) == "2.0 KB"
    end

    test "formats bytes" do
      assert ManagePanel.format_file_size(512) == "512 B"
    end
  end

  describe "file_summary/2" do
    test "formats singular file count" do
      assert ManagePanel.file_summary(1, 1_073_741_824) == "1 file, 1.0 GB"
    end

    test "formats plural file count" do
      assert ManagePanel.file_summary(3, 3_145_728) == "3 files, 3.0 MB"
    end
  end

  describe "build_file_groups/2" do
    test "groups files by directory" do
      files = [
        %{file: %{file_path: "/media/movies/Sample Movie/movie.mkv"}, size: 4_000_000_000},
        %{file: %{file_path: "/media/movies/Sample Movie/extras.mkv"}, size: 1_000_000_000}
      ]

      result = ManagePanel.build_file_groups(files, MapSet.new())

      assert [%{dir: "/media/movies/Sample Movie", name: "Sample Movie", files: files_list}] =
               result

      assert length(files_list) == 2
    end

    test "sorts groups by directory path" do
      files = [
        %{file: %{file_path: "/z-dir/movie.mkv"}, size: 100},
        %{file: %{file_path: "/a-dir/movie.mkv"}, size: 200}
      ]

      result = ManagePanel.build_file_groups(files, MapSet.new())

      assert [%{dir: "/a-dir"}, %{dir: "/z-dir"}] = result
    end

    test "sorts files within a group by filename" do
      # Files arrive in discovery order, which for a scraped season is
      # effectively random — the ledger must read E01, E02, … regardless.
      files = [
        %{file: %{file_path: "/dir/Sample.Show.S01E05.mkv"}, size: 100},
        %{file: %{file_path: "/dir/Sample.Show.S01E12.mkv"}, size: 100},
        %{file: %{file_path: "/dir/Sample.Show.S01E01.mkv"}, size: 100}
      ]

      [%{files: sorted}] = ManagePanel.build_file_groups(files, MapSet.new())

      assert Enum.map(sorted, &Path.basename(&1.file.file_path)) == [
               "Sample.Show.S01E01.mkv",
               "Sample.Show.S01E05.mkv",
               "Sample.Show.S01E12.mkv"
             ]
    end

    test "flags media directories" do
      files = [
        %{file: %{file_path: "/watch/movie.mkv"}, size: 100},
        %{file: %{file_path: "/other/movie.mkv"}, size: 200}
      ]

      media_dirs = MapSet.new(["/watch"])
      result = ManagePanel.build_file_groups(files, media_dirs)

      watch_group = Enum.find(result, &(&1.dir == "/watch"))
      other_group = Enum.find(result, &(&1.dir == "/other"))

      assert watch_group.is_media_dir == true
      assert other_group.is_media_dir == false
    end

    test "returns empty list for empty files" do
      assert ManagePanel.build_file_groups([], MapSet.new()) == []
    end
  end

  describe "effective_expanded_dirs/2" do
    defp groups_with(counts) do
      counts
      |> Enum.with_index()
      |> Enum.map(fn {count, index} ->
        dir = "/dir-#{index}"

        %{
          dir: dir,
          name: "dir-#{index}",
          is_media_dir: false,
          files: for(n <- 1..count, do: %{file: %{file_path: "#{dir}/file-#{n}.mkv"}, size: 1})
        }
      end)
    end

    test "nil with a small inventory (≤ 6 files total) expands every group" do
      groups = groups_with([2, 3])

      assert ManagePanel.effective_expanded_dirs(groups, nil) ==
               MapSet.new(["/dir-0", "/dir-1"])
    end

    test "nil with a large inventory collapses every group" do
      groups = groups_with([4, 4])

      assert ManagePanel.effective_expanded_dirs(groups, nil) == MapSet.new()
    end

    test "an explicit set passes through untouched, whatever the inventory size" do
      groups = groups_with([1])

      assert ManagePanel.effective_expanded_dirs(groups, MapSet.new(["/x"])) ==
               MapSet.new(["/x"])

      assert ManagePanel.effective_expanded_dirs(groups, MapSet.new()) == MapSet.new()
    end

    test "no groups means nothing to expand" do
      assert ManagePanel.effective_expanded_dirs([], nil) == MapSet.new()
    end
  end

  describe "build_delete_all_payload/2" do
    test "builds grouped payload with totals" do
      files = [
        %{file: %{file_path: "/media/SampleShow/ep1.mkv"}, size: 4_000_000_000},
        %{file: %{file_path: "/media/SampleShow/ep2.mkv"}, size: 3_000_000_000},
        %{file: %{file_path: "/other/movie.mkv"}, size: 2_000_000_000}
      ]

      result = ManagePanel.build_delete_all_payload(files, MapSet.new())

      assert result.file_count == 3
      assert result.total_size == 9_000_000_000

      assert length(result.file_groups) == 2

      show_group = Enum.find(result.file_groups, &(&1.name == "SampleShow"))
      assert length(show_group.files) == 2
      assert Enum.all?(show_group.files, &Map.has_key?(&1, :path))
      assert Enum.all?(show_group.files, &Map.has_key?(&1, :name))
      assert Enum.all?(show_group.files, &Map.has_key?(&1, :size))
    end

    test "flags media directories in payload" do
      files = [
        %{file: %{file_path: "/watch/movie.mkv"}, size: 100}
      ]

      result = ManagePanel.build_delete_all_payload(files, MapSet.new(["/watch"]))

      assert [%{is_media_dir: true}] = result.file_groups
    end

    test "handles nil sizes gracefully" do
      files = [
        %{file: %{file_path: "/dir/movie.mkv"}, size: nil},
        %{file: %{file_path: "/dir/other.mkv"}, size: 1000}
      ]

      result = ManagePanel.build_delete_all_payload(files, MapSet.new())

      assert result.total_size == 1000
      assert result.file_count == 2
    end
  end
end
