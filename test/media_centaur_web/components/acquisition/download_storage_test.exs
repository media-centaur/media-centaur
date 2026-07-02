defmodule MediaCentaurWeb.Components.Acquisition.DownloadStorageTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Components.Acquisition.DownloadStorage

  @gib 1_073_741_824

  defp drive(mount_point, role_labels) do
    %{
      mount_point: mount_point,
      device: "/dev/x",
      total_bytes: 1000,
      used_bytes: 100,
      usage_percent: 10,
      roles: Enum.map(role_labels, &%{label: &1, path: mount_point})
    }
  end

  # A drive with real byte figures so storage_severity/1 classifies it.
  defp sized_drive(total_gib, used_gib, usage_percent) do
    %{
      mount_point: "/mnt/media",
      device: "/dev/x",
      total_bytes: round(total_gib * @gib),
      used_bytes: round(used_gib * @gib),
      usage_percent: usage_percent,
      roles: [%{label: "Media dir", path: "/mnt/media"}]
    }
  end

  describe "media_dir_drives/1" do
    test "keeps drives that host a media directory" do
      media = drive("/mnt/media", ["Media dir", "Image cache"])
      assert DownloadStorage.media_dir_drives([media]) == [media]
    end

    test "drops drives that only hold the database or an image cache" do
      db_only = drive("/", ["Database", "Image cache"])
      assert DownloadStorage.media_dir_drives([db_only]) == []
    end

    test "keeps only the media-hosting drives from a mixed set" do
      media = drive("/mnt/media", ["Media dir"])
      db_only = drive("/", ["Database", "Image cache"])
      assert DownloadStorage.media_dir_drives([media, db_only]) == [media]
    end

    test "is empty for an empty list" do
      assert DownloadStorage.media_dir_drives([]) == []
    end
  end

  describe "display_mode/1" do
    test "empty when there are no drives" do
      assert DownloadStorage.display_mode([]) == :empty
    end

    test "calm for a single healthy drive" do
      # 500 GiB free, 50% used → :ok
      assert DownloadStorage.display_mode([sized_drive(1000, 500, 50)]) == :calm
    end

    test "card for a single low drive (earns the space)" do
      # 15 GiB free → :critical
      assert DownloadStorage.display_mode([sized_drive(30, 15, 50)]) == :card
    end

    test "card for multiple drives even when all healthy" do
      healthy = sized_drive(1000, 500, 50)
      assert DownloadStorage.display_mode([healthy, healthy]) == :card
    end
  end

  describe "calm_summary/1" do
    test "reads free space and mount point for a single drive" do
      assert DownloadStorage.calm_summary([sized_drive(1000, 500, 50)]) ==
               "500 GiB free on /mnt/media"
    end

    test "is nil unless there is exactly one drive" do
      assert DownloadStorage.calm_summary([]) == nil
      d = sized_drive(1000, 500, 50)
      assert DownloadStorage.calm_summary([d, d]) == nil
    end
  end
end
